@isTest
private class QueryProductByNameTest {

    @testSetup
    static void setup() {
        insert new Product2(Name = 'CRM Bundle', ProductCode = 'CRM-001', IsActive = true);
    }

    @isTest
    static void testMatchFound() {
        QueryProductByName.Request req = new QueryProductByName.Request();
        req.productName = 'CRM';
        List<QueryProductByName.Result> results =
            QueryProductByName.execute(new List<QueryProductByName.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assert(results[0].matchCount >= 1, 'Expected at least one match');
        System.assert(results[0].recordsJson.contains('CRM Bundle'));
    }

    @isTest
    static void testNoMatch() {
        QueryProductByName.Request req = new QueryProductByName.Request();
        req.productName = 'ZZZ Nonexistent Product';
        List<QueryProductByName.Result> results =
            QueryProductByName.execute(new List<QueryProductByName.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(0, results[0].matchCount);
    }

    @isTest
    static void testBlankNameFails() {
        QueryProductByName.Request req = new QueryProductByName.Request();
        req.productName = '';
        List<QueryProductByName.Result> results =
            QueryProductByName.execute(new List<QueryProductByName.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }
}
