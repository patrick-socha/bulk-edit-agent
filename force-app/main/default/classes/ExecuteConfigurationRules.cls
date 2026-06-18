public with sharing class ExecuteConfigurationRules {

    private static final String ENDPOINT_PATH = '/revenue/product-configurator/rules/actions/execute';

    @InvocableMethod(
        label='Execute Configuration Rules'
        description='Run configuration rules for a specific quote or order (API v67.0+)'
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
            if (String.isNotBlank(req.transactionContextId)) {
                body.put('transactionContextId', req.transactionContextId);
            }
            if (String.isNotBlank(req.transactionId)) {
                body.put('transactionId', req.transactionId);
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
            label='Transaction Context ID'
            description='Required if transactionId is not provided'
            required=false
        )
        public String transactionContextId;

        @InvocableVariable(
            label='Transaction ID'
            description='Required if transactionContextId is not provided'
            required=false
        )
        public String transactionId;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if configuration rules executed successfully'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Response Body'
            description='Full raw JSON response from the API including messageRules, visibilityRules, etc.'
        )
        public String responseBody;
    }
}
