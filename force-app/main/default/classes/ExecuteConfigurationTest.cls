@isTest
private class ExecuteConfigurationTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true,"messages":{}}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"CONFIG_ERROR","message":"Rule violation"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        ExecuteConfiguration.Request req = new ExecuteConfiguration.Request();
        req.transactionId = '0Q0000000000001';
        List<ExecuteConfiguration.Result> results =
            ExecuteConfiguration.execute(new List<ExecuteConfiguration.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        ExecuteConfiguration.Request req = new ExecuteConfiguration.Request();
        req.transactionId = 'bad-txn';
        List<ExecuteConfiguration.Result> results =
            ExecuteConfiguration.execute(new List<ExecuteConfiguration.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }
}
