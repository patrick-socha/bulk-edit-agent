public with sharing class GetAttributePicklistValues {

    @InvocableMethod(
        label='Get Attribute Picklist Values'
        description='Given the current AttributePicklistValue ID of a configurator attribute (from the GetConfiguratorInstance JSON), return all valid picklist values for that attribute as JSON, each with its id, value, and displayValue. Use this to map a user-requested value to the picklist value ID needed by UpdateConfiguratorNodes.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        // ── Resolve each current value ID to its owning picklist, bulk-safe ──
        Set<Id> currentValueIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isNotBlank(req.currentPicklistValueId)) {
                try { currentValueIds.add((Id) req.currentPicklistValueId); } catch (Exception e) {}
            }
        }

        // Map: current value ID -> its PicklistId
        Map<Id, Id> valueToPicklist = new Map<Id, Id>();
        if (!currentValueIds.isEmpty()) {
            for (AttributePicklistValue v : [
                SELECT Id, PicklistId
                FROM AttributePicklistValue
                WHERE Id IN :currentValueIds
                WITH USER_MODE
            ]) {
                valueToPicklist.put(v.Id, v.PicklistId);
            }
        }

        // Gather all involved picklist IDs and query their values once
        Set<Id> picklistIds = new Set<Id>(valueToPicklist.values());
        Map<Id, List<AttributePicklistValue>> valuesByPicklist = new Map<Id, List<AttributePicklistValue>>();
        if (!picklistIds.isEmpty()) {
            for (AttributePicklistValue v : [
                SELECT Id, Name, Value, DisplayValue, Code, Sequence, PicklistId
                FROM AttributePicklistValue
                WHERE PicklistId IN :picklistIds
                WITH USER_MODE
                ORDER BY Sequence
            ]) {
                if (!valuesByPicklist.containsKey(v.PicklistId)) {
                    valuesByPicklist.put(v.PicklistId, new List<AttributePicklistValue>());
                }
                valuesByPicklist.get(v.PicklistId).add(v);
            }
        }

        // ── Build a result per request ──
        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.currentPicklistValueId)) {
                    r.isSuccess = false;
                    r.errorMessage = 'currentPicklistValueId is required.';
                    results.add(r);
                    continue;
                }
                Id plId = valueToPicklist.get((Id) req.currentPicklistValueId);
                if (plId == null) {
                    r.isSuccess = false;
                    r.errorMessage = 'No picklist found for value ' + req.currentPicklistValueId +
                        '. The attribute may not be a picklist attribute.';
                    results.add(r);
                    continue;
                }
                List<Map<String, Object>> values = new List<Map<String, Object>>();
                for (AttributePicklistValue v : valuesByPicklist.get(plId)) {
                    values.add(new Map<String, Object>{
                        'id' => v.Id,
                        'value' => v.Value,
                        'displayValue' => v.DisplayValue,
                        'name' => v.Name,
                        'code' => v.Code
                    });
                }
                r.isSuccess = true;
                r.valueCount = values.size();
                r.valuesJson = JSON.serialize(values);
            } catch (Exception e) {
                r.isSuccess = false;
                r.errorMessage = e.getMessage();
            }
            results.add(r);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Current Picklist Value ID'
            description='The AttributePicklistValue ID currently set on the attribute (read from the GetConfiguratorInstance JSON field AttributePicklistValue)'
            required=true
        )
        public String currentPicklistValueId;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the picklist values were retrieved'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Values JSON'
            description='JSON array of valid picklist values, each with id, value, displayValue, name, code'
        )
        public String valuesJson;

        @InvocableVariable(
            label='Value Count'
            description='Number of valid picklist values'
        )
        public Integer valueCount;
    }
}
