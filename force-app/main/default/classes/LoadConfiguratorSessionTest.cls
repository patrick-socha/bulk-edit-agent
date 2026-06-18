@isTest
private class LoadConfiguratorSessionTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true,"contextId":"ctx_001"}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"BAD_REQUEST","message":"Invalid transactionId"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        LoadConfiguratorSession.Request req = new LoadConfiguratorSession.Request();
        req.transactionId = '0Q0000000000001';
        List<LoadConfiguratorSession.Result> results =
            LoadConfiguratorSession.execute(new List<LoadConfiguratorSession.Request>{ req });
        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals('ctx_001', results[0].contextId);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        LoadConfiguratorSession.Request req = new LoadConfiguratorSession.Request();
        req.transactionId = 'bad-id';
        List<LoadConfiguratorSession.Result> results =
            LoadConfiguratorSession.execute(new List<LoadConfiguratorSession.Request>{ req });
        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }
}
