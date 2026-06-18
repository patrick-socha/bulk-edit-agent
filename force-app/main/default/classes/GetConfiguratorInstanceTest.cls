@isTest
private class GetConfiguratorInstanceTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true,"transaction":{"id":"txn1"}}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"INVALID_CONTEXT","message":"Context not found"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        GetConfiguratorInstance.Request req = new GetConfiguratorInstance.Request();
        req.contextId = 'ctx_001';
        List<GetConfiguratorInstance.Result> results =
            GetConfiguratorInstance.execute(new List<GetConfiguratorInstance.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assertNotEquals(null, results[0].transactionJson);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        GetConfiguratorInstance.Request req = new GetConfiguratorInstance.Request();
        req.contextId = 'bad-ctx';
        List<GetConfiguratorInstance.Result> results =
            GetConfiguratorInstance.execute(new List<GetConfiguratorInstance.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }
}
