@isTest
private class ManageSavedConfigurationTest {

    private class ListSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"success":true,"savedConfigurations":[]}');
            return resp;
        }
    }

    private class SaveSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(200);
            resp.setBody('{"id":"savedCfg_001"}');
            return resp;
        }
    }

    private class FailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(400);
            resp.setBody('{"success":false,"errors":[{"code":"BAD_REQUEST","message":"Missing required field"}]}');
            return resp;
        }
    }

    @isTest
    static void testListSuccess() {
        Test.setMock(HttpCalloutMock.class, new ListSuccessMock());
        ManageSavedConfiguration.Request req = new ManageSavedConfiguration.Request();
        req.operation = 'LIST';
        req.referenceRecordId = '0Q0000000000001';
        List<ManageSavedConfiguration.Result> results =
            ManageSavedConfiguration.execute(new List<ManageSavedConfiguration.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
    }

    @isTest
    static void testSaveSuccess() {
        Test.setMock(HttpCalloutMock.class, new SaveSuccessMock());
        ManageSavedConfiguration.Request req = new ManageSavedConfiguration.Request();
        req.operation = 'SAVE';
        req.referenceRecordId = '0Q0000000000001';
        req.savedConfigName = 'My Template';
        List<ManageSavedConfiguration.Result> results =
            ManageSavedConfiguration.execute(new List<ManageSavedConfiguration.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals('savedCfg_001', results[0].savedConfigId);
    }

    @isTest
    static void testInvalidOperation() {
        ManageSavedConfiguration.Request req = new ManageSavedConfiguration.Request();
        req.operation = 'BOGUS';
        List<ManageSavedConfiguration.Result> results =
            ManageSavedConfiguration.execute(new List<ManageSavedConfiguration.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage.contains('Invalid operation'));
    }

    @isTest
    static void testFailure() {
        Test.setMock(HttpCalloutMock.class, new FailureMock());
        ManageSavedConfiguration.Request req = new ManageSavedConfiguration.Request();
        req.operation = 'LIST';
        req.referenceRecordId = 'bad-id';
        List<ManageSavedConfiguration.Result> results =
            ManageSavedConfiguration.execute(new List<ManageSavedConfiguration.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
    }
}
