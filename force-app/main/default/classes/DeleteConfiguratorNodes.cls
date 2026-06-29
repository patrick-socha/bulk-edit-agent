public with sharing class DeleteConfiguratorNodes {

    private static final String ACTION = 'delete-nodes';

    @InvocableMethod(
        label='Delete Configurator Nodes'
        description='Remove nodes (line items or bundle components) from a product configuration session'
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
            body.put('deletedNodes', JSON.deserializeUntyped(req.deletedNodesJson));
            if (String.isNotBlank(req.configuratorOptionsJson)) {
                body.put('configuratorOptions', JSON.deserializeUntyped(req.configuratorOptionsJson));
            }

            // Route through the shared client for the full 120s timeout (see
            // ConfiguratorClient.callConfigurator); the default 10s timed out on slow calls.
            HttpResponse resp = ConfiguratorClient.callConfigurator(ACTION, body);

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
            label='Deleted Nodes JSON'
            description='JSON array of Configurator Deleted Node Input objects (each has a path array)'
            required=true
        )
        public String deletedNodesJson;

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
            description='True if all nodes were deleted successfully'
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
