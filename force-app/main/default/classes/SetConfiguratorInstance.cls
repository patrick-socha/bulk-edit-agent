public with sharing class SetConfiguratorInstance {

    private static final String ENDPOINT_PATH = '/connect/cpq/configurator/actions/set-instance';

    @InvocableMethod(
        label='Set Configurator Instance'
        description='Set a product configuration instance from an external JSON payload; returns a contextId like load-instance'
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
            body.put('contextMappingId', req.contextMappingId);
            body.put('transaction', req.transactionJson);
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
                r.contextId = (String) parsed.get('contextId');
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
            label='Context Mapping ID'
            description='The contextMappingId that identifies the configuration context to set'
            required=true
        )
        public String contextMappingId;

        @InvocableVariable(
            label='Transaction JSON'
            description='Stringified JSON payload representing the full transaction to load'
            required=true
        )
        public String transactionJson;

        @InvocableVariable(
            label='Configurator Options JSON'
            description='Optional JSON string of Configurator Options Input'
            required=false
        )
        public String configuratorOptionsJson;
    }

    public class Result {
        @InvocableVariable(
            label='Context ID'
            description='Session handle for subsequent configurator calls'
        )
        public String contextId;

        @InvocableVariable(
            label='Is Success'
            description='True if the instance was set successfully'
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
