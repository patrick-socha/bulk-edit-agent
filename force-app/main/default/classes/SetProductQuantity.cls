public with sharing class SetProductQuantity {

    private static final String ENDPOINT_PATH = '/connect/cpq/configurator/actions/set-product-quantity';

    @InvocableMethod(
        label='Set Product Quantity'
        description='Set the quantity of a product on an existing QuoteLineItem through the configurator runtime'
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
            body.put('quantity', req.quantity);
            body.put('transactionLinePath', JSON.deserializeUntyped(req.transactionLinePathJson));
            if (String.isNotBlank(req.configuratorOptionsJson)) {
                body.put('configuratorOptions', JSON.deserializeUntyped(req.configuratorOptionsJson));
            }

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

    public class Request {
        @InvocableVariable(
            label='Context ID'
            description='Session handle returned by LoadConfiguratorSession'
            required=true
        )
        public String contextId;

        @InvocableVariable(
            label='Quantity'
            description='The new quantity to set on the product'
            required=true
        )
        public Integer quantity;

        @InvocableVariable(
            label='Transaction Line Path JSON'
            description='JSON array representing the path to the line item, e.g. ["Quote.QuoteLineItem.Quantity"]'
            required=true
        )
        public String transactionLinePathJson;

        @InvocableVariable(
            label='Configurator Options JSON'
            description='Optional JSON string of Configurator Options Input'
            required=false
        )
        public String configuratorOptionsJson;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the quantity was set successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Response Body'
            description='Full raw JSON response from the API'
        )
        public String responseBody;
    }
}
