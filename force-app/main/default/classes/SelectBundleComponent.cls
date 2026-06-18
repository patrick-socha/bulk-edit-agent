public with sharing class SelectBundleComponent {

    @InvocableMethod(
        label='Select Bundle Component'
        description='Select (turn on) or deselect (turn off) a predefined bundle component option on a quote, honoring the bundle component rules. operation = SELECT requires productRelatedComponentId; operation = DESELECT requires selectedLineItemId. Never creates a new product or deletes an arbitrary record — only toggles predefined options. If a bundle rule (e.g. minimum selection) prevents the change, it is NOT saved and the rule message is returned.'
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
        try {
            String op = req.operation != null ? req.operation.toUpperCase() : '';
            if (op != 'SELECT' && op != 'DESELECT') {
                r.isSuccess = false;
                r.errorMessage = 'operation must be SELECT or DESELECT.';
                return r;
            }
            if (String.isBlank(req.quoteId) || String.isBlank(req.bundleLineItemId)) {
                r.isSuccess = false;
                r.errorMessage = 'quoteId and bundleLineItemId are required.';
                return r;
            }

            // 1) Load a configurator session
            String ctx = ConfiguratorClient.loadSession(req.quoteId);
            if (ctx == null) {
                r.isSuccess = false;
                r.errorMessage = 'Could not start a configurator session for the quote.';
                return r;
            }

            // 2) Build the mutation (validated) and call add-nodes or delete-nodes
            HttpResponse mutResp;
            if (op == 'SELECT') {
                mutResp = doSelect(req, ctx);
            } else {
                mutResp = doDeselect(req, ctx);
            }
            if (mutResp == null) {
                // a validation method already set the error on r via exception path; guard anyway
                r.isSuccess = false;
                if (String.isBlank(r.errorMessage)) {
                    r.errorMessage = 'The component change could not be prepared.';
                }
                return r;
            }
            r.responseBody = mutResp.getBody();

            // 3) Inspect the mutation response for hard errors and bundle-rule messages
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(mutResp.getBody());
            Boolean apiOk = parsed.get('success') == true;
            String ruleMessage = ConfiguratorClient.extractBlockingMessage(parsed);

            if (!apiOk) {
                r.isSuccess = false;
                Object errs = parsed.get('errors');
                r.errorMessage = errs != null ? JSON.serialize(errs) : 'The configurator rejected the change.';
                return r;
            }
            if (ruleMessage != null) {
                // A bundle rule (e.g. min/max selection) prevents this change. Do NOT save.
                r.isSuccess = false;
                r.ruleBlocked = true;
                r.errorMessage = ruleMessage;
                return r;
            }

            // 4) No blocking rule — commit
            HttpResponse saveResp = ConfiguratorClient.saveSession(ctx);
            Map<String, Object> saveParsed = (Map<String, Object>) JSON.deserializeUntyped(saveResp.getBody());
            if (saveResp.getStatusCode() >= 200 && saveResp.getStatusCode() < 300 && saveParsed.get('success') == true) {
                r.isSuccess = true;
                r.message = op == 'SELECT' ? 'Component selected and saved.' : 'Component deselected and saved.';
            } else {
                r.isSuccess = false;
                r.errorMessage = 'Save failed: ' + saveResp.getBody();
            }
        } catch (Exception e) {
            r.isSuccess = false;
            r.errorMessage = e.getMessage();
        }
        return r;
    }

    // ── SELECT: validate the PRC, resolve pricing, add the two nodes (via shared util) ──
    private static HttpResponse doSelect(Request req, String ctx) {
        if (String.isBlank(req.productRelatedComponentId)) {
            throw new SelectException('productRelatedComponentId is required for SELECT.');
        }
        // Validate the PRC is a real predefined option.
        List<ProductRelatedComponent> prcs = [
            SELECT Id, ChildProductId, ParentProductId, ParentProduct.Name
            FROM ProductRelatedComponent
            WHERE Id = :req.productRelatedComponentId
            WITH USER_MODE
        ];
        if (prcs.isEmpty()) {
            throw new SelectException('The specified component option does not exist.');
        }
        ProductRelatedComponent prc = prcs[0];

        Id pbId = [SELECT Pricebook2Id FROM Quote WHERE Id = :req.quoteId WITH USER_MODE].Pricebook2Id;
        PricebookEntry pbe = ConfiguratorClient.resolvePricebookEntry(prc.ChildProductId, pbId);

        // Single-instance refSuffix = the PRC id (preserves prior behavior).
        List<Object> nodes = ConfiguratorClient.buildSelectNodes(
            req.quoteId, req.bundleLineItemId, prc, pbe,
            String.valueOf(Math.abs(req.productRelatedComponentId.hashCode())));

        Map<String, Object> body = new Map<String, Object>{
            'contextId' => ctx,
            'addedNodes' => nodes
        };
        return ConfiguratorClient.callConfigurator('add-nodes', body);
    }

    // ── DESELECT: validate the line item is on the quote, then delete its node ──
    private static HttpResponse doDeselect(Request req, String ctx) {
        if (String.isBlank(req.selectedLineItemId)) {
            throw new SelectException('selectedLineItemId is required for DESELECT.');
        }
        List<QuoteLineItem> qlis = [
            SELECT Id FROM QuoteLineItem
            WHERE Id = :req.selectedLineItemId AND QuoteId = :req.quoteId
            WITH USER_MODE
        ];
        if (qlis.isEmpty()) {
            throw new SelectException('That component is not on this quote.');
        }
        Map<String, Object> body = new Map<String, Object>{
            'contextId' => ctx,
            'deletedNodes' => new List<Object>{
                ConfiguratorClient.buildDeleteNode(req.quoteId, req.selectedLineItemId)
            }
        };
        return ConfiguratorClient.callConfigurator('delete-nodes', body);
    }

    public class SelectException extends Exception {}

    public class Request {
        @InvocableVariable(
            label='Operation'
            description='SELECT to turn on a predefined option, DESELECT to turn one off'
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
            label='Bundle Line Item ID'
            description='The QuoteLineItem ID of the parent bundle on the quote'
            required=true
        )
        public String bundleLineItemId;

        @InvocableVariable(
            label='Product Related Component ID'
            description='SELECT only: the predefined component option to turn on (from ListBundleComponentOptions)'
            required=false
        )
        public String productRelatedComponentId;

        @InvocableVariable(
            label='Selected Line Item ID'
            description='DESELECT only: the QuoteLineItem ID of the currently-selected component to turn off'
            required=false
        )
        public String selectedLineItemId;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True only if the change was applied AND saved to the quote'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Rule Blocked'
            description='True if a bundle rule (e.g. minimum selection) prevented the change; nothing was saved'
        )
        public Boolean ruleBlocked;

        @InvocableVariable(
            label='Message'
            description='Human-readable success message'
        )
        public String message;

        @InvocableVariable(
            label='Error Message'
            description='Error or bundle-rule message when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Response Body'
            description='Raw configurator response for the mutation step'
        )
        public String responseBody;
    }
}
