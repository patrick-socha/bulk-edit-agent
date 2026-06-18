@isTest
private class GetAttributePicklistValuesTest {

    @isTest
    static void testBlankInputFails() {
        GetAttributePicklistValues.Request req = new GetAttributePicklistValues.Request();
        req.currentPicklistValueId = '';
        List<GetAttributePicklistValues.Result> results =
            GetAttributePicklistValues.execute(new List<GetAttributePicklistValues.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @isTest
    static void testUnknownValueIdReturnsError() {
        // A well-formed but non-existent AttributePicklistValue ID: query finds nothing,
        // so the helper reports a clean "no picklist found" failure rather than throwing.
        GetAttributePicklistValues.Request req = new GetAttributePicklistValues.Request();
        req.currentPicklistValueId = '0v6000000000001AAA';
        List<GetAttributePicklistValues.Result> results =
            GetAttributePicklistValues.execute(new List<GetAttributePicklistValues.Request>{ req });
        System.assertEquals(false, results[0].isSuccess);
        System.assert(results[0].errorMessage != null);
    }

    @isTest
    static void testLiveDataIfPresent() {
        // If the org already has picklist values (it does in the configured RLM org),
        // exercise the success path against a real one so coverage includes the happy path.
        List<AttributePicklistValue> existing = [
            SELECT Id FROM AttributePicklistValue LIMIT 1
        ];
        if (existing.isEmpty()) {
            return; // no data to exercise; blank/unknown tests cover the rest
        }
        GetAttributePicklistValues.Request req = new GetAttributePicklistValues.Request();
        req.currentPicklistValueId = existing[0].Id;
        List<GetAttributePicklistValues.Result> results =
            GetAttributePicklistValues.execute(new List<GetAttributePicklistValues.Request>{ req });
        System.assertEquals(true, results[0].isSuccess);
        System.assert(results[0].valueCount >= 1);
    }
}
