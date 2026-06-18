@isTest
private class BulkSelectBundleComponentTest {

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

    private class RuleBlockedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            if (req.getEndpoint().contains('load-instance')) {
                resp.setBody('{"success":true,"contextId":"ctx_test"}');
            } else {
                resp.setBody('{"success":true,"errors":[],"configuratorMessages":{"b":[{"messageType":"warning","category":"bundlevalidation","message":"Select child products in the range 1-1 and try again."}]}}');
            }
            return resp;
        }
    }

    @isTest
    static void testInvalidOperation() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'BOGUS';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('SELECT or DESELECT'));
    }

    @isTest
    static void testSelectMissingPrc() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'SELECT';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        // no productRelatedComponentId
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('productRelatedComponentId'));
    }

    @isTest
    static void testDeselectMissingChild() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'DESELECT';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        // no childProductId
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('childProductId'));
    }

    @isTest
    static void testNoInstancesFound() {
        // Valid inputs but no matching bundle instances on the (non-existent) quote.
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'SELECT';
        req.quoteId = '0Q0000000000123AAA';
        req.bundleProductId = '01t000000000123AAA';
        req.productRelatedComponentId = '0dS000000000123AAA';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertEquals(0, res[0].totalBundles);
        System.assert(res[0].errorMessage.contains('No instances'));
    }

    @isTest
    static void testConfiguratorClientHelpers() {
        // Exercise the shared util's pure builders (no callout).
        ProductRelatedComponent prc = new ProductRelatedComponent();
        // ChildProductId left null is fine for node-shape coverage.
        PricebookEntry pbe = new PricebookEntry();
        List<Object> nodes = ConfiguratorClient.buildSelectNodes(
            '0Q0000000000001AAA', '0QL000000000001AAA', prc, pbe, '1_999');
        System.assertEquals(2, nodes.size(), 'Expected QLI + relationship nodes');
        Map<String, Object> relNode = (Map<String, Object>) nodes[1];
        Map<String, Object> relObj = (Map<String, Object>) relNode.get('addedObject');
        System.assertEquals('QuoteLineRelationship', relObj.get('businessObjectType'),
            'Relationship node must use QuoteLineRelationship');
        Map<String, Object> del = ConfiguratorClient.buildDeleteNode('0Q0000000000001AAA', '0QL000000000002AAA');
        System.assert(del.containsKey('path'));
    }

    @isTest
    static void testExtractBlockingMessage() {
        Map<String, Object> blocked = (Map<String, Object>) JSON.deserializeUntyped(
            '{"configuratorMessages":{"b":[{"messageType":"warning","category":"bundlevalidation","message":"range 1-1"}]}}');
        System.assertNotEquals(null, ConfiguratorClient.extractBlockingMessage(blocked));
        Map<String, Object> clean = (Map<String, Object>) JSON.deserializeUntyped(
            '{"configuratorMessages":{}}');
        System.assertEquals(null, ConfiguratorClient.extractBlockingMessage(clean));
    }
}
