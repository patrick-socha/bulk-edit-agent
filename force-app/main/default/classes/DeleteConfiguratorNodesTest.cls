@isTest
private class DeleteConfiguratorNodesTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"NODE_NOT_FOUND","message":"Node not found"}]}');
            return resp;
        }
    }

    @isTest
    static void testSuccess() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        DeleteConfiguratorNodes.Request req = new DeleteConfiguratorNodes.Request();
        req.contextId = 'ctx_001';
        req.deletedNodesJson = '[{"path":["0Q0000000000001","0a0000000000001"]}]';
        List<DeleteConfiguratorNodes.Result> results =
            DeleteConfiguratorNodes.execute(new List<DeleteConfiguratorNodes.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        DeleteConfiguratorNodes.Request req = new DeleteConfiguratorNodes.Request();
        req.contextId = 'bad-ctx';
        req.deletedNodesJson = '[{}]';
        List<DeleteConfiguratorNodes.Result> results =
            DeleteConfiguratorNodes.execute(new List<DeleteConfiguratorNodes.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
    }
}
