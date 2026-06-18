/**
 * Applies the SAME component change (SELECT or DESELECT) to EVERY instance of a bundle
 * product on a quote, deterministically, in ONE configurator session with ONE save.
 *
 * Why this exists: a quote can have multiple instances of the same bundle. The LLM is
 * unreliable at looping "do X for each of N", so the loop lives here in Apex. And because
 * save-instance is a whole-quote replace, all instance mutations happen in a single session
 * and are committed by a single save (all-or-nothing).
 *
 * All-or-nothing: if ANY instance is blocked by a bundle rule or errors, NOTHING is saved.
 */
public with sharing class BulkSelectBundleComponent {

    // 1 load + N mutations + 1 save must stay under the 100-callout governor limit.
    private static final Integer MAX_INSTANCES = 93;

    @InvocableMethod(
        label='Bulk Select Bundle Component'
        description='Apply the same component SELECT or DESELECT to every instance of a bundle product on a quote, in one pass. SELECT needs productRelatedComponentId; DESELECT needs childProductId. All-or-nothing: if any instance is blocked by bundle rules, nothing is saved. Reports per-bundle results. Never creates new products or deletes arbitrary records — only toggles predefined options.'
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
            if (op != 'SELECT' && op != 'DESELECT') {
                return fail(r, 'operation must be SELECT or DESELECT.');
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

            // 1) Discover every instance of the bundle product on the quote.
            List<QuoteLineItem> bundleInstances = [
                SELECT Id FROM QuoteLineItem
                WHERE QuoteId = :req.quoteId AND Product2Id = :req.bundleProductId
                WITH USER_MODE
            ];
            r.totalBundles = bundleInstances.size();
            if (bundleInstances.isEmpty()) {
                return fail(r, 'No instances of that bundle were found on the quote.');
            }
            if (bundleInstances.size() > MAX_INSTANCES) {
                return fail(r, 'Too many bundle instances (' + bundleInstances.size() +
                    ') to process safely in one operation. Please narrow the scope.');
            }
            Set<Id> instanceIds = new Set<Id>();
            for (QuoteLineItem qli : bundleInstances) { instanceIds.add(qli.Id); }

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

            // 3) For SELECT, resolve the PRC + its child product + price ONCE (shared by all).
            ProductRelatedComponent prc;
            PricebookEntry pbe;
            Id targetChildProductId;
            if (op == 'SELECT') {
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
                targetChildProductId = prc.ChildProductId;
                Id pbId = [SELECT Pricebook2Id FROM Quote WHERE Id = :req.quoteId WITH USER_MODE].Pricebook2Id;
                pbe = ConfiguratorClient.resolvePricebookEntry(prc.ChildProductId, pbId);
            } else {
                targetChildProductId = (Id) req.childProductId;
            }

            // 4) One session for all instances.
            String ctx = ConfiguratorClient.loadSession(req.quoteId);
            if (ctx == null) {
                return fail(r, 'Could not start a configurator session for the quote.');
            }

            // 5) Stage each instance; track per-bundle status. Sequential mutation calls in
            //    the SAME session (works regardless of multi-parent-per-call support).
            Boolean anyBlockedOrFailed = false;
            Integer idx = 0;
            for (Id bundleLineItemId : instanceIds) {
                idx++;
                Map<String, Object> entry = new Map<String, Object>{ 'bundleLineItemId' => bundleLineItemId };

                Boolean alreadyHasChild = childrenByParent.get(bundleLineItemId).contains(targetChildProductId);

                if (op == 'SELECT' && alreadyHasChild) {
                    entry.put('status', 'SKIPPED_ALREADY');
                    entry.put('detail', 'Component already selected on this bundle.');
                    r.skippedCount++;
                    perBundle.add(entry);
                    continue;
                }
                if (op == 'DESELECT' && !alreadyHasChild) {
                    entry.put('status', 'SKIPPED_ALREADY');
                    entry.put('detail', 'Component is not selected on this bundle.');
                    r.skippedCount++;
                    perBundle.add(entry);
                    continue;
                }

                // Build + send the mutation for this instance.
                HttpResponse resp;
                if (op == 'SELECT') {
                    List<Object> nodes = ConfiguratorClient.buildSelectNodes(
                        req.quoteId, bundleLineItemId, prc, pbe,
                        idx + '_' + String.valueOf(Math.abs(req.productRelatedComponentId.hashCode())));
                    resp = ConfiguratorClient.callConfigurator('add-nodes',
                        new Map<String, Object>{ 'contextId' => ctx, 'addedNodes' => nodes });
                } else {
                    Id childItemId = childItemByParent.get(bundleLineItemId).get(targetChildProductId);
                    resp = ConfiguratorClient.callConfigurator('delete-nodes',
                        new Map<String, Object>{ 'contextId' => ctx,
                            'deletedNodes' => new List<Object>{
                                ConfiguratorClient.buildDeleteNode(req.quoteId, childItemId) } });
                }

                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                Boolean apiOk = parsed.get('success') == true;
                String ruleMessage = ConfiguratorClient.extractBlockingMessage(parsed);

                if (!apiOk) {
                    entry.put('status', 'FAILED');
                    Object errs = parsed.get('errors');
                    entry.put('detail', errs != null ? JSON.serialize(errs) : 'Configurator rejected the change.');
                    r.failedCount++;
                    anyBlockedOrFailed = true;
                } else if (ruleMessage != null) {
                    entry.put('status', 'RULE_BLOCKED');
                    entry.put('detail', ruleMessage);
                    r.ruleBlockedCount++;
                    anyBlockedOrFailed = true;
                } else {
                    entry.put('status', op == 'SELECT' ? 'SELECTED' : 'DESELECTED');
                    r.changedCount++;
                }
                perBundle.add(entry);
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
                String verb = op == 'SELECT' ? 'Added the component to' : 'Removed the component from';
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

    public class Request {
        @InvocableVariable(
            label='Operation'
            description='SELECT to turn a component on for every bundle instance, DESELECT to turn it off'
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
            description='SELECT only: the predefined component option to turn on across all instances (from ListBundleComponentOptions)'
            required=false
        )
        public String productRelatedComponentId;

        @InvocableVariable(
            label='Child Product ID'
            description='DESELECT only: the Product2 ID of the component to turn off across all instances'
            required=false
        )
        public String childProductId;
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
            description='Per-instance JSON: bundleLineItemId, status (SELECTED|DESELECTED|SKIPPED_ALREADY|RULE_BLOCKED|FAILED), detail'
        )
        public String resultsJson;

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
