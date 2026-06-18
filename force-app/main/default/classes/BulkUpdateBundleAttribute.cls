/**
 * Sets the SAME attribute value (e.g. Operating System = Redhat Enterprise Linux) on EVERY
 * instance of a bundle product on a quote, deterministically, in ONE configurator session
 * with ONE save (all-or-nothing).
 *
 * Handles both picklist attributes (validates the requested value against the picklist's
 * allowed values UP FRONT and sets AttributePicklistValue) and free-text/numeric attributes
 * (sets AttributeValue directly). If the requested value is invalid for a picklist, NOTHING
 * is changed and the allowed values are returned.
 */
public with sharing class BulkUpdateBundleAttribute {

    private static final Integer MAX_INSTANCES = 93; // 1 load + N updates + 1 save < 100 callouts

    @InvocableMethod(
        label='Bulk Update Bundle Attribute'
        description='Set the same attribute value on every instance of a bundle product on a quote, in one pass. Provide attributeName and desiredValue (display value or value). Picklist attributes are validated against allowed values up front. All-or-nothing: if any instance is blocked, nothing is saved. Reports per-bundle results.'
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
            if (String.isBlank(req.quoteId) || String.isBlank(req.bundleProductId)
                    || String.isBlank(req.attributeName) || String.isBlank(req.desiredValue)) {
                return fail(r, 'quoteId, bundleProductId, attributeName, and desiredValue are all required.');
            }

            // 1) Discover bundle instances.
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

            // 2) Find the named attribute on each instance (one query).
            //    attrByParent: bundleLineItemId -> the QuoteLineItemAttribute for attributeName
            Map<Id, QuoteLineItemAttribute> attrByParent = new Map<Id, QuoteLineItemAttribute>();
            for (QuoteLineItemAttribute a : [
                SELECT Id, AttributeName, AttributeValue, AttributePicklistValueId, QuoteLineItemId
                FROM QuoteLineItemAttribute
                WHERE QuoteLineItemId IN :instanceIds AND AttributeName = :req.attributeName
                WITH USER_MODE
            ]) {
                attrByParent.put(a.QuoteLineItemId, a);
            }
            if (attrByParent.isEmpty()) {
                return fail(r, 'None of the bundle instances have an attribute named "' +
                    req.attributeName + '".');
            }

            // 3) Determine picklist vs free-text and resolve/validate the target value ONCE.
            //    A picklist attribute has a non-null AttributePicklistValueId on the existing row.
            Boolean isPicklist = false;
            for (QuoteLineItemAttribute a : attrByParent.values()) {
                if (a.AttributePicklistValueId != null) { isPicklist = true; }
                break;
            }

            String attributeKey;   // 'AttributePicklistValue' or 'AttributeValue'
            String targetValue;    // picklist-value Id, or the literal text

            if (isPicklist) {
                // Resolve the picklist that governs this attribute (from any instance's current value).
                Id sampleValueId;
                for (QuoteLineItemAttribute a : attrByParent.values()) {
                    if (a.AttributePicklistValueId != null) { sampleValueId = a.AttributePicklistValueId; break; }
                }
                Id picklistId = [
                    SELECT PicklistId FROM AttributePicklistValue WHERE Id = :sampleValueId WITH USER_MODE
                ].PicklistId;

                // Validate desiredValue against allowed values (match Value or DisplayValue, case-insensitive).
                List<AttributePicklistValue> allowed = [
                    SELECT Id, Value, DisplayValue FROM AttributePicklistValue
                    WHERE PicklistId = :picklistId WITH USER_MODE
                ];
                String wanted = req.desiredValue.trim().toLowerCase();
                List<String> allowedLabels = new List<String>();
                for (AttributePicklistValue v : allowed) {
                    allowedLabels.add(v.DisplayValue != null ? v.DisplayValue : v.Value);
                    if ((v.Value != null && v.Value.toLowerCase() == wanted)
                            || (v.DisplayValue != null && v.DisplayValue.toLowerCase() == wanted)) {
                        targetValue = v.Id;
                    }
                }
                if (targetValue == null) {
                    return fail(r, '"' + req.desiredValue + '" is not a valid value for ' +
                        req.attributeName + '. Allowed values: ' + String.join(allowedLabels, ', ') + '.');
                }
                attributeKey = 'AttributePicklistValue';
            } else {
                attributeKey = 'AttributeValue';
                targetValue = req.desiredValue;
            }

            // 4) One session for all instances.
            String ctx = ConfiguratorClient.loadSession(req.quoteId);
            if (ctx == null) {
                return fail(r, 'Could not start a configurator session for the quote.');
            }

            // 5) Stage each instance.
            Boolean anyBlockedOrFailed = false;
            for (Id bundleLineItemId : instanceIds) {
                Map<String, Object> entry = new Map<String, Object>{ 'bundleLineItemId' => bundleLineItemId };
                QuoteLineItemAttribute attr = attrByParent.get(bundleLineItemId);

                if (attr == null) {
                    entry.put('status', 'FAILED');
                    entry.put('detail', 'This bundle instance has no "' + req.attributeName + '" attribute.');
                    r.failedCount++;
                    anyBlockedOrFailed = true;
                    perBundle.add(entry);
                    continue;
                }

                // Idempotency: already at the desired value?
                Boolean already = isPicklist
                    ? (attr.AttributePicklistValueId == (Id) targetValue)
                    : (attr.AttributeValue != null && attr.AttributeValue.equalsIgnoreCase(targetValue));
                if (already) {
                    entry.put('status', 'SKIPPED_ALREADY');
                    entry.put('detail', 'Already set to the requested value.');
                    r.skippedCount++;
                    perBundle.add(entry);
                    continue;
                }

                Map<String, Object> updNode = ConfiguratorClient.buildUpdateAttributeNode(
                    req.quoteId, bundleLineItemId, attr.Id, attributeKey, targetValue);
                HttpResponse resp = ConfiguratorClient.callConfigurator('update-nodes',
                    new Map<String, Object>{ 'contextId' => ctx, 'updatedNodes' => new List<Object>{ updNode } });

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
                    entry.put('status', 'UPDATED');
                    r.changedCount++;
                }
                perBundle.add(entry);
            }

            r.resultsJson = JSON.serialize(perBundle);

            // 6) All-or-nothing.
            if (anyBlockedOrFailed) {
                r.isSuccess = false;
                r.saved = false;
                r.errorMessage = 'One or more bundles could not be updated (' +
                    r.ruleBlockedCount + ' blocked by rules, ' + r.failedCount +
                    ' failed). No changes were saved.';
                r.message = 'No changes saved. ' + r.changedCount + ' of ' + r.totalBundles +
                    ' bundles could have been updated, but ' + (r.ruleBlockedCount + r.failedCount) +
                    ' could not, so the whole operation was cancelled.';
                return r;
            }

            if (r.changedCount == 0) {
                r.isSuccess = true;
                r.saved = false;
                r.message = 'All ' + r.totalBundles + ' bundle instances were already set to "' +
                    req.desiredValue + '". No changes needed.';
                return r;
            }

            // 7) Commit once.
            HttpResponse saveResp = ConfiguratorClient.saveSession(ctx);
            Map<String, Object> saveParsed = (Map<String, Object>) JSON.deserializeUntyped(saveResp.getBody());
            if (saveResp.getStatusCode() >= 200 && saveResp.getStatusCode() < 300 && saveParsed.get('success') == true) {
                r.isSuccess = true;
                r.saved = true;
                r.message = 'Set ' + req.attributeName + ' to "' + req.desiredValue + '" on ' +
                    r.changedCount + ' of ' + r.totalBundles + ' bundle instances' +
                    (r.skippedCount > 0 ? ' (' + r.skippedCount + ' already set).' : '.');
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
        @InvocableVariable(label='Operation' description='Always BULK_UPDATE_ATTRIBUTE (reserved for clarity)' required=false)
        public String operation;

        @InvocableVariable(label='Quote ID' description='The Quote being configured' required=true)
        public String quoteId;

        @InvocableVariable(
            label='Bundle Product ID'
            description='The Product2 ID of the bundle. Every QuoteLineItem instance of this product on the quote is updated.'
            required=true
        )
        public String bundleProductId;

        @InvocableVariable(
            label='Attribute Name'
            description='The attribute to set, exactly as it appears on the bundle (e.g. "Operating System", "Base Core Count")'
            required=true
        )
        public String attributeName;

        @InvocableVariable(
            label='Desired Value'
            description='The value to set. For a picklist attribute this is matched (case-insensitive) against the allowed values and rejected if invalid; for a free-text attribute it is used literally.'
            required=true
        )
        public String desiredValue;
    }

    public class Result {
        @InvocableVariable(label='Is Success' description='True only if committed (or all instances already set)')
        public Boolean isSuccess;
        @InvocableVariable(label='Saved' description='True if a save was committed')
        public Boolean saved;
        @InvocableVariable(label='Total Bundles' description='Number of bundle instances found')
        public Integer totalBundles = 0;
        @InvocableVariable(label='Changed Count' description='Instances actually updated')
        public Integer changedCount = 0;
        @InvocableVariable(label='Skipped Count' description='Instances already at the requested value')
        public Integer skippedCount = 0;
        @InvocableVariable(label='Rule Blocked Count' description='Instances a bundle rule prevented from changing')
        public Integer ruleBlockedCount = 0;
        @InvocableVariable(label='Failed Count' description='Instances that errored')
        public Integer failedCount = 0;
        @InvocableVariable(label='Results JSON' description='Per-instance: bundleLineItemId, status (UPDATED|SKIPPED_ALREADY|RULE_BLOCKED|FAILED), detail')
        public String resultsJson;
        @InvocableVariable(label='Message' description='Human-readable rollup')
        public String message;
        @InvocableVariable(label='Error Message' description='Error or rule-block summary when isSuccess is false (includes allowed values for invalid picklist input)')
        public String errorMessage;
    }
}
