public with sharing class GetConfiguratorInstance {

    private static final String ENDPOINT_PATH = '/connect/cpq/configurator/actions/get-instance';

    @InvocableMethod(
        label='Get Configurator Instance'
        description='Fetch the full JSON representation of the current product configuration for a session'
        callout=true
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
            Map<String, Object> body = new Map<String, Object>();
            body.put('contextId', req.contextId);

            HttpRequest httpReq = new HttpRequest();
            httpReq.setEndpoint('callout:Configurator_API/services/data/v67.0' + ENDPOINT_PATH);
            httpReq.setHeader('Content-Type', 'application/json');
            httpReq.setMethod('POST');
            httpReq.setBody(JSON.serialize(body));

            Http http = new Http();
            HttpResponse resp = http.send(httpReq);

            r.responseBody = resp.getBody();
            if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
                Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
                r.isSuccess = parsed.get('success') == true;
                Object txn = parsed.get('transaction');
                r.transactionJson = txn != null ? JSON.serialize(txn) : null;
                r.attributesJson = buildAttributeSummary(txn);
                if (!r.isSuccess) {
                    Object errs = parsed.get('errors');
                    r.errorMessage = errs != null ? JSON.serialize(errs) : 'Unknown error from API';
                }
            } else {
                r.isSuccess = false;
                r.errorMessage = 'HTTP ' + resp.getStatusCode() + ': ' + resp.getBody();
            }
        } catch (Exception e) {
            r.isSuccess = false;
            r.errorMessage = e.getMessage();
        }
        return r;
    }

    // Walks transaction -> SalesTransaction[] -> SalesTransactionItem[] ->
    // SalesTransactionItemAttribute[] and returns a compact summary the LLM can use to
    // inspect attributes and pick the node to update — WITHOUT the full multi-hundred-KB
    // transaction payload (which overflows agent session context).
    @SuppressWarnings('PMD.CyclomaticComplexity')
    private static String buildAttributeSummary(Object txn) {
        List<Object> lineItems = new List<Object>();
        try {
            if (!(txn instanceof Map<String, Object>)) {
                return null;
            }
            Map<String, Object> txnMap = (Map<String, Object>) txn;
            Object stListObj = txnMap.get('SalesTransaction');
            if (!(stListObj instanceof List<Object>)) {
                return null;
            }
            for (Object stObj : (List<Object>) stListObj) {
                if (!(stObj instanceof Map<String, Object>)) { continue; }
                Object itemsObj = ((Map<String, Object>) stObj).get('SalesTransactionItem');
                if (!(itemsObj instanceof List<Object>)) { continue; }
                for (Object itemObj : (List<Object>) itemsObj) {
                    if (!(itemObj instanceof Map<String, Object>)) { continue; }
                    Map<String, Object> item = (Map<String, Object>) itemObj;
                    Map<String, Object> liSummary = new Map<String, Object>{
                        'lineItemId' => item.get('id'),
                        'product' => item.get('Product'),
                        'productName' => item.get('ProductName'),
                        'quantity' => item.get('Quantity')
                    };
                    List<Object> attrSummaries = new List<Object>();
                    Object attrsObj = item.get('SalesTransactionItemAttribute');
                    if (attrsObj instanceof List<Object>) {
                        for (Object aObj : (List<Object>) attrsObj) {
                            if (!(aObj instanceof Map<String, Object>)) { continue; }
                            Map<String, Object> a = (Map<String, Object>) aObj;
                            attrSummaries.add(new Map<String, Object>{
                                'attributeNodeId' => a.get('id'),
                                'attributeName' => a.get('AttributeName'),
                                'currentValue' => a.get('AttributeValue'),
                                'currentPicklistValueId' => a.get('AttributePicklistValue'),
                                'isPicklist' => a.get('AttributePicklistValue') != null
                            });
                        }
                    }
                    liSummary.put('attributes', attrSummaries);
                    lineItems.add(liSummary);
                }
            }
            return JSON.serialize(lineItems);
        } catch (Exception e) {
            // Summary is best-effort; never fail the whole action over it.
            return null;
        }
    }

    public class Request {
        @InvocableVariable(
            label='Context ID'
            description='Session handle returned by LoadConfiguratorSession'
            required=true
        )
        public String contextId;
    }

    public class Result {
        @InvocableVariable(
            label='Transaction'
            description='Serialized JSON of the full transaction / configuration state (large; keep internal)'
        )
        public String transactionJson;

        @InvocableVariable(
            label='Attributes Summary'
            description='Compact JSON: per line item, its attributes with attributeNodeId, attributeName, currentValue, currentPicklistValueId, isPicklist'
        )
        public String attributesJson;

        @InvocableVariable(
            label='Is Success'
            description='True if the instance was retrieved successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Response Body'
            description='Full raw JSON response from the API for downstream parsing'
        )
        public String responseBody;
    }
}
