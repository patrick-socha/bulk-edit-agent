/**
 * Applies the SAME component change (SELECT, DESELECT, or SWAP) to EVERY instance of a bundle
 * product on a quote, deterministically, in ONE configurator session with ONE save.
 *
 * Why this exists: a quote can have multiple instances of the same bundle. The LLM is
 * unreliable at looping "do X for each of N", so the loop lives here in Apex. And because
 * save-instance is a whole-quote replace, all instance mutations happen in a single session
 * and are committed by a single save (all-or-nothing).
 *
 * SWAP replaces one option with another within the SAME session: it stages the removal of the
 * old option (delete-nodes) and the addition of the new one (add-nodes) before saving. This is
 * required for single-select groups (min=1/max=1, e.g. a "Consumption" group): doing the
 * deselect or the select alone leaves the group transiently out of range, which the configurator
 * reports as a blocking message. By sending both moves in one session and judging ONLY the final
 * batch's rule result, the group is never observed out of range at commit. (Verified via live
 * read-only probe: delete-then-add on a min=1/max=1 group ends with no blocking message.)
 *
 * All-or-nothing: if ANY instance is blocked by a bundle rule or errors, NOTHING is saved.
 */
public with sharing class BulkSelectBundleComponent {

    // 1 load + N mutations + 1 save must stay under the 100-callout governor limit.
    private static final Integer MAX_INSTANCES = 93;

    @InvocableMethod(
        label='Bulk Select Bundle Component'
        description='Apply the same component SELECT, DESELECT, or SWAP to every instance of a bundle product on a quote, in one pass. SELECT needs productRelatedComponentId. DESELECT needs childProductId. SWAP replaces one option with another in a single-select group and needs BOTH productRelatedComponentId (the new option) and childProductId (the Product2 Id of the option to remove). All-or-nothing: if any instance is blocked by bundle rules, nothing is saved. Reports per-bundle results. Never creates new products or deletes arbitrary records — only toggles predefined options.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request req : requests) {
            results.add(process(req));
        }
        return results;
    }

    private static Result process(Request req) {
        Result r = new Result();
        List<Map<String, Object>> perBundle = new List<Map<String, Object>>();
        try {
            String op = req.operation != null ? req.operation.toUpperCase() : '';
            if (op != 'SELECT' && op != 'DESELECT' && op != 'SWAP') {
                return fail(r, 'operation must be SELECT, DESELECT, or SWAP.');
            }
            if (String.isBlank(req.quoteId) || String.isBlank(req.bundleProductId)) {
                return fail(r, 'quoteId and bundleProductId are required.');
            }
            if (op == 'SELECT' && String.isBlank(req.productRelatedComponentId)) {
                return fail(r, 'productRelatedComponentId is required for SELECT.');
            }
            if (op == 'DESELECT' && String.isBlank(req.childProductId)) {
                return fail(r, 'childProductId is required for DESELECT.');
            }
            if (op == 'SWAP' && (String.isBlank(req.productRelatedComponentId) || String.isBlank(req.childProductId))) {
                return fail(r, 'SWAP requires productRelatedComponentId (the new option) and childProductId (the option to remove).');
            }

            // 0) Resolve optional group/region scope BEFORE any callout, so an unknown
            //    group name fails for free. Blank groupNames => whole quote (unchanged).
            //    NOTE: this only narrows which instances we MUTATE; loadSession still loads
            //    the WHOLE quote and save-instance replaces the whole quote, so out-of-scope
            //    groups are always preserved. Do NOT push scoping into loadSession.
            QuoteLineGroupScope.ScopeResult scope =
                QuoteLineGroupScope.resolveFromCsv(req.quoteId, req.groupNames);
            r.scopeDescription = scope.scopingRequested ? scope.scopeDescription : 'entire quote';
            if (scope.scopingRequested && !scope.unmatchedTokens.isEmpty()) {
                return fail(r, 'These group names were not found on the quote: ' +
                    String.join(scope.unmatchedTokens, ', ') + '. Available groups: ' +
                    String.join(scope.availableGroupNames, ', ') + '.');
            }

            // 1) Discover every instance of the bundle product on the quote (+ its group).
            List<QuoteLineItem> bundleInstances = [
                SELECT Id, QuoteLineGroupId FROM QuoteLineItem
                WHERE QuoteId = :req.quoteId AND Product2Id = :req.bundleProductId
                WITH USER_MODE
            ];
            // Narrow to the requested groups (incl. their subgroups) when scoping.
            Set<Id> instanceIds = new Set<Id>();
            for (QuoteLineItem qli : bundleInstances) {
                if (scope.scopingRequested && !scope.groupIds.contains(qli.QuoteLineGroupId)) {
                    continue;
                }
                instanceIds.add(qli.Id);
            }
            r.totalBundles = instanceIds.size(); // scoped count
            if (instanceIds.isEmpty()) {
                return fail(r, scope.scopingRequested
                    ? 'No instances of that bundle were found in the requested group(s): ' +
                        scope.scopeDescription + '.'
                    : 'No instances of that bundle were found on the quote.');
            }
            if (instanceIds.size() > MAX_INSTANCES) {
                return fail(r, 'Too many bundle instances (' + instanceIds.size() +
                    ') to process safely in one operation. Please narrow the scope.');
            }

            // 2) Existing children of all instances (idempotency + DESELECT resolution).
            //    childrenByParent: bundleLineItemId -> set of child Product2Ids it already has
            //    childItemByParent: bundleLineItemId -> (childProduct2Id -> child lineItemId)
            Map<Id, Set<Id>> childrenByParent = new Map<Id, Set<Id>>();
            Map<Id, Map<Id, Id>> childItemByParent = new Map<Id, Map<Id, Id>>();
            for (Id bid : instanceIds) {
                childrenByParent.put(bid, new Set<Id>());
                childItemByParent.put(bid, new Map<Id, Id>());
            }
            for (QuoteLineItem child : [
                SELECT Id, Product2Id, ParentQuoteLineItemId
                FROM QuoteLineItem
                WHERE QuoteId = :req.quoteId AND ParentQuoteLineItemId IN :instanceIds
                WITH USER_MODE
            ]) {
                childrenByParent.get(child.ParentQuoteLineItemId).add(child.Product2Id);
                childItemByParent.get(child.ParentQuoteLineItemId).put(child.Product2Id, child.Id);
            }

            // 3) Resolve what each op needs ONCE (shared across all instances):
            //    - SELECT/SWAP need the new option's PRC + its child product + price.
            //    - DESELECT/SWAP need the Product2 Id of the option being turned off.
            ProductRelatedComponent prc;           // the option being turned ON (SELECT/SWAP)
            PricebookEntry pbe;
            Id targetChildProductId;                // SELECT: product to add. DESELECT: product to remove.
            Id removeChildProductId;                // SWAP only: the product to remove
            if (op == 'SELECT' || op == 'SWAP') {
                List<ProductRelatedComponent> prcs = [
                    SELECT Id, ChildProductId, ParentProductId
                    FROM ProductRelatedComponent
                    WHERE Id = :req.productRelatedComponentId
                    WITH USER_MODE
                ];
                if (prcs.isEmpty()) {
                    return fail(r, 'The specified component option does not exist.');
                }
                prc = prcs[0];
                targetChildProductId = prc.ChildProductId; // the product we are turning ON
                Id pbId = [SELECT Pricebook2Id FROM Quote WHERE Id = :req.quoteId WITH USER_MODE].Pricebook2Id;
                pbe = ConfiguratorClient.resolvePricebookEntry(prc.ChildProductId, pbId);
            }
            if (op == 'DESELECT') {
                targetChildProductId = (Id) req.childProductId;
            }
            if (op == 'SWAP') {
                removeChildProductId = (Id) req.childProductId;
            }

            // 4) One session for all instances.
            String ctx = ConfiguratorClient.loadSession(req.quoteId);
            if (ctx == null) {
                return fail(r, 'Could not start a configurator session for the quote.');
            }

            // 5) Stage each instance into up to TWO batches that run in the SAME session:
            //    a delete-nodes batch (DESELECT, and the "remove old" half of a SWAP) and an
            //    add-nodes batch (SELECT, and the "add new" half of a SWAP). For a SWAP the
            //    group is momentarily out of range between the two calls (e.g. 0 then 1 in a
            //    min=1/max=1 group), which the configurator reports as a transient blocking
            //    message; that message is IGNORED and only the FINAL batch's result decides
            //    the outcome. Batching also avoids N sequential slow callouts (Read timed out).
            Boolean anyBlockedOrFailed = false;
            Integer idx = 0;
            List<Object> deleteNodes = new List<Object>();
            List<Object> addNodes = new List<Object>();
            List<Map<String, Object>> stagedEntries = new List<Map<String, Object>>();
            String okStatus = (op == 'SELECT') ? 'SELECTED' : (op == 'DESELECT') ? 'DESELECTED' : 'SWAPPED';

            for (Id bundleLineItemId : instanceIds) {
                idx++;
                Map<String, Object> entry = new Map<String, Object>{ 'bundleLineItemId' => bundleLineItemId };
                Set<Id> existing = childrenByParent.get(bundleLineItemId);
                String refSuffix = idx + '_' + String.valueOf(Math.abs(
                    (op == 'DESELECT' ? req.childProductId : req.productRelatedComponentId).hashCode()));

                if (op == 'SELECT') {
                    if (existing.contains(targetChildProductId)) {
                        skip(r, perBundle, entry, 'Component already selected on this bundle.');
                        continue;
                    }
                    addNodes.addAll(ConfiguratorClient.buildSelectNodes(
                        req.quoteId, bundleLineItemId, prc, pbe, refSuffix));

                } else if (op == 'DESELECT') {
                    if (!existing.contains(targetChildProductId)) {
                        skip(r, perBundle, entry, 'Component is not selected on this bundle.');
                        continue;
                    }
                    deleteNodes.add(ConfiguratorClient.buildDeleteNode(
                        req.quoteId, childItemByParent.get(bundleLineItemId).get(targetChildProductId)));

                } else { // SWAP: remove the old option and add the new one in the same session
                    Boolean hasNew = existing.contains(targetChildProductId);
                    Boolean hasOld = existing.contains(removeChildProductId);
                    if (hasNew && !hasOld) {
                        skip(r, perBundle, entry, 'Already set to the new option on this bundle.');
                        continue;
                    }
                    if (!hasOld) {
                        // The specific option to remove is not selected here; do not force a
                        // standalone add (that would push a single-select group out of range).
                        skip(r, perBundle, entry, 'The option to swap out is not selected on this bundle; skipped.');
                        continue;
                    }
                    deleteNodes.add(ConfiguratorClient.buildDeleteNode(
                        req.quoteId, childItemByParent.get(bundleLineItemId).get(removeChildProductId)));
                    if (!hasNew) {
                        addNodes.addAll(ConfiguratorClient.buildSelectNodes(
                            req.quoteId, bundleLineItemId, prc, pbe, refSuffix));
                    }
                }
                stagedEntries.add(entry); // status set after the batch calls
            }

            // Execute the staged batches in one session: delete first, then add. The LAST
            // batch sent is the one whose rule-block result is authoritative; an earlier
            // batch's transient block (mid-swap, group out of range) is ignored, but a hard
            // API failure on any batch still aborts.
            Boolean hasDelete = !deleteNodes.isEmpty();
            Boolean hasAdd = !addNodes.isEmpty();
            if (hasDelete || hasAdd) {
                String batchError = null;   // hard failure detail
                String batchBlock = null;   // rule-block detail from the FINAL batch

                if (hasDelete) {
                    Map<String, Object> delParsed = sendBatch(ctx, 'delete-nodes', 'deletedNodes', deleteNodes);
                    if (delParsed.get('success') != true) {
                        Object errs = delParsed.get('errors');
                        batchError = errs != null ? JSON.serialize(errs) : 'Configurator rejected the removal.';
                    } else if (!hasAdd) {
                        // delete is the final batch (DESELECT) -> its block is authoritative
                        batchBlock = ConfiguratorClient.extractBlockingMessage(delParsed);
                    }
                }
                if (batchError == null && hasAdd) {
                    Map<String, Object> addParsed = sendBatch(ctx, 'add-nodes', 'addedNodes', addNodes);
                    if (addParsed.get('success') != true) {
                        Object errs = addParsed.get('errors');
                        batchError = errs != null ? JSON.serialize(errs) : 'Configurator rejected the change.';
                    } else {
                        // add is the final batch (SELECT/SWAP) -> its block is authoritative
                        batchBlock = ConfiguratorClient.extractBlockingMessage(addParsed);
                    }
                }

                if (batchError != null || batchBlock != null) {
                    anyBlockedOrFailed = true;
                    String status = (batchBlock != null) ? 'RULE_BLOCKED' : 'FAILED';
                    String detail = (batchBlock != null) ? batchBlock : batchError;
                    if (batchBlock != null) { r.ruleBlockedCount += stagedEntries.size(); }
                    else { r.failedCount += stagedEntries.size(); }
                    for (Map<String, Object> e : stagedEntries) {
                        e.put('status', status);
                        e.put('detail', detail);
                        perBundle.add(e);
                    }
                } else {
                    for (Map<String, Object> e : stagedEntries) {
                        e.put('status', okStatus);
                        perBundle.add(e);
                        r.changedCount++;
                    }
                }
            }

            r.resultsJson = JSON.serialize(perBundle);

            // 6) All-or-nothing: any block/failure → do NOT save.
            if (anyBlockedOrFailed) {
                r.isSuccess = false;
                r.saved = false;
                r.errorMessage = 'One or more bundles could not be changed (' +
                    r.ruleBlockedCount + ' blocked by rules, ' + r.failedCount +
                    ' failed). No changes were saved.';
                r.message = 'No changes saved. ' + r.changedCount + ' of ' + r.totalBundles +
                    ' bundles could have been updated, but ' + (r.ruleBlockedCount + r.failedCount) +
                    ' could not, so the whole operation was cancelled.';
                return r;
            }

            // Nothing actually staged (all already in desired state) → idempotent success, no save.
            if (r.changedCount == 0) {
                r.isSuccess = true;
                r.saved = false;
                r.message = 'All ' + r.totalBundles + ' bundle instances were already in the requested state. No changes needed.';
                return r;
            }

            // 7) Commit once.
            HttpResponse saveResp = ConfiguratorClient.saveSession(ctx);
            Map<String, Object> saveParsed = (Map<String, Object>) JSON.deserializeUntyped(saveResp.getBody());
            if (saveResp.getStatusCode() >= 200 && saveResp.getStatusCode() < 300 && saveParsed.get('success') == true) {
                r.isSuccess = true;
                r.saved = true;
                String verb = op == 'SELECT' ? 'Added the component to'
                    : op == 'DESELECT' ? 'Removed the component from'
                    : 'Swapped the component on';
                r.message = verb + ' ' + r.changedCount + ' of ' + r.totalBundles + ' bundle instances' +
                    (r.skippedCount > 0 ? ' (' + r.skippedCount + ' already in the requested state).' : '.');
            } else {
                r.isSuccess = false;
                r.saved = false;
                r.errorMessage = 'Save failed: ' + saveResp.getBody();
            }
        } catch (Exception e) {
            r.isSuccess = false;
            r.errorMessage = e.getMessage();
            if (r.resultsJson == null && !perBundle.isEmpty()) {
                r.resultsJson = JSON.serialize(perBundle);
            }
        }
        return r;
    }

    private static Result fail(Result r, String msg) {
        r.isSuccess = false;
        r.saved = false;
        r.errorMessage = msg;
        return r;
    }

    /** Record a per-instance skip (already in the desired state, or nothing to do here). */
    private static void skip(Result r, List<Map<String, Object>> perBundle,
            Map<String, Object> entry, String detail) {
        entry.put('status', 'SKIPPED_ALREADY');
        entry.put('detail', detail);
        r.skippedCount++;
        perBundle.add(entry);
    }

    /** Send one mutation batch in the session and return the parsed response. */
    private static Map<String, Object> sendBatch(String ctx, String action, String nodeKey, List<Object> nodes) {
        HttpResponse resp = ConfiguratorClient.callConfigurator(action,
            new Map<String, Object>{ 'contextId' => ctx, nodeKey => nodes });
        return (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    }

    public class Request {
        @InvocableVariable(
            label='Operation'
            description='SELECT to turn a component on for every bundle instance, DESELECT to turn it off, SWAP to replace one option with another (e.g. in a single-select group)'
            required=true
        )
        public String operation;

        @InvocableVariable(
            label='Quote ID'
            description='The Quote being configured'
            required=true
        )
        public String quoteId;

        @InvocableVariable(
            label='Bundle Product ID'
            description='The Product2 ID of the bundle. Every QuoteLineItem instance of this product on the quote is updated.'
            required=true
        )
        public String bundleProductId;

        @InvocableVariable(
            label='Product Related Component ID'
            description='SELECT or SWAP: the predefined component option to turn ON across all instances (from ListBundleComponentOptions)'
            required=false
        )
        public String productRelatedComponentId;

        @InvocableVariable(
            label='Child Product ID'
            description='DESELECT: the Product2 ID of the component to turn off. SWAP: the Product2 ID of the option to remove (replaced by productRelatedComponentId).'
            required=false
        )
        public String childProductId;

        @InvocableVariable(
            label='Group Names'
            description='Optional. Comma-separated group/region names to limit the change to, e.g. "California, New York". Matched groups include their subgroups automatically. Leave blank to apply to every instance on the quote.'
            required=false
        )
        public String groupNames;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True only if the operation committed (or all instances were already in the requested state)'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Saved'
            description='True if a save was committed to the quote'
        )
        public Boolean saved;

        @InvocableVariable(
            label='Total Bundles'
            description='Number of bundle instances found on the quote'
        )
        public Integer totalBundles = 0;

        @InvocableVariable(
            label='Changed Count'
            description='Number of instances actually changed'
        )
        public Integer changedCount = 0;

        @InvocableVariable(
            label='Skipped Count'
            description='Number of instances already in the requested state'
        )
        public Integer skippedCount = 0;

        @InvocableVariable(
            label='Rule Blocked Count'
            description='Number of instances a bundle rule prevented from changing'
        )
        public Integer ruleBlockedCount = 0;

        @InvocableVariable(
            label='Failed Count'
            description='Number of instances that errored'
        )
        public Integer failedCount = 0;

        @InvocableVariable(
            label='Results JSON'
            description='Per-instance JSON: bundleLineItemId, status (SELECTED|DESELECTED|SWAPPED|SKIPPED_ALREADY|RULE_BLOCKED|FAILED), detail'
        )
        public String resultsJson;

        @InvocableVariable(
            label='Scope Description'
            description='Which groups/regions the change was limited to (e.g. "New York, California (incl. Los Angeles, San Francisco)"), or "entire quote" when not scoped. Use this in the response so the rep knows exactly what was affected.'
        )
        public String scopeDescription;

        @InvocableVariable(
            label='Message'
            description='Human-readable rollup of the bulk operation'
        )
        public String message;

        @InvocableVariable(
            label='Error Message'
            description='Error or rule-block summary when isSuccess is false'
        )
        public String errorMessage;
    }
}
