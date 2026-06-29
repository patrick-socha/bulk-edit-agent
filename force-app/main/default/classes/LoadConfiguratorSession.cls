public with sharing class LoadConfiguratorSession {

    private static final String ACTION = 'load-instance';

    @InvocableMethod(
        label='Load Configurator Session'
        description='Create a configurator session for a transaction and return a contextId handle for subsequent calls'
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
        r.quoteId = req.transactionId;
        try {
            Map<String, Object> body = new Map<String, Object>();
            body.put('transactionId', req.transactionId);
            if (String.isNotBlank(req.configuratorOptionsJson)) {
                body.put('configuratorOptions', JSON.deserializeUntyped(req.configuratorOptionsJson));
            }

            // Route through the shared client so this callout gets the full 120s timeout
            // (the configurator API is slow per call; the default 10s timed out and forced
            // the agent to retry, doubling the turn). See ConfiguratorClient.callConfigurator.
            HttpResponse resp = ConfiguratorClient.callConfigurator(ACTION, body);

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
            label='Transaction ID'
            description='The quote or order ID that identifies the transaction to load into a configurator session'
            required=true
        )
        public String transactionId;

        @InvocableVariable(
            label='Configurator Options JSON'
            description='Optional JSON string of Configurator Options Input (executePricing, executeConfigurationRules, etc.)'
            required=false
        )
        public String configuratorOptionsJson;
    }

    public class Result {
        @InvocableVariable(
            label='Context ID'
            description='Session handle returned by load-instance; pass to all subsequent configurator calls'
        )
        public String contextId;

        @InvocableVariable(
            label='Quote ID'
            description='Echo of the transactionId (Quote ID) that started this session, for downstream use'
        )
        public String quoteId;

        @InvocableVariable(
            label='Is Success'
            description='True if the session was created successfully'
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
