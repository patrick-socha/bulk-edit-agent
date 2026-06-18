@isTest
private class BulkUpdateBundleAttributeTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            if (req.getEndpoint().contains('load-instance')) {
                resp.setBody('{"success":true,"contextId":"ctx_test"}');
            } else if (req.getEndpoint().contains('save-instance')) {
                resp.setBody('{"success":true,"errors":[]}');
            } else {
                resp.setBody('{"success":true,"errors":[],"configuratorMessages":{}}');
            }
            return resp;
        }
    }

    @isTest
    static void testMissingInputs() {
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = '0Q0000000000001AAA';
        // missing bundleProductId / attributeName / desiredValue
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertNotEquals(null, res[0].errorMessage);
    }

    @isTest
    static void testNoInstancesFound() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = '0Q0000000000123AAA';
        req.bundleProductId = '01t000000000123AAA';
        req.attributeName = 'Operating System';
        req.desiredValue = 'Redhat Enterprise Linux';
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertEquals(0, res[0].totalBundles);
        System.assert(res[0].errorMessage.contains('No instances'));
    }

    @isTest
    static void testBuildUpdateNodeShape() {
        // Exercise the shared util's update-node builder for both attribute kinds.
        Map<String, Object> pick = ConfiguratorClient.buildUpdateAttributeNode(
            '0Q0000000000001AAA', '0QL000000000001AAA', '0zu000000000001AAA',
            'AttributePicklistValue', '0v6000000000001AAA');
        List<Object> path = (List<Object>) pick.get('path');
        System.assertEquals(3, path.size(), 'attribute path must be 3 segments');
        Map<String, Object> upd = (Map<String, Object>) pick.get('updatedAttributes');
        System.assert(upd.containsKey('AttributePicklistValue'));

        Map<String, Object> text = ConfiguratorClient.buildUpdateAttributeNode(
            '0Q0000000000001AAA', '0QL000000000001AAA', '0zu000000000001AAA',
            'AttributeValue', '8');
        Map<String, Object> updT = (Map<String, Object>) text.get('updatedAttributes');
        System.assertEquals('8', updT.get('AttributeValue'));
    }
}
