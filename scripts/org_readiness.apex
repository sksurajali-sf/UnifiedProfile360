/*
 * Unified Profile 360 — org readiness check.
 *
 * Answers one question: will this org's Data Cloud naming work with the app? It depends on
 * nothing the package installs, so it can be run before installing, or against an old version,
 * and it only reads.
 *
 * HOW TO RUN
 *   1. Open the following URL in a browser tab already logged in to the org, and copy the
 *      unifiedDmoName values it lists:
 *        /services/data/v67.0/ssot/identity-resolutions
 *   2. Paste them into UNIFIED_DMOS below, one per ruleset.
 *   3. Setup -> Developer Console -> Debug -> Open Execute Anonymous Window, tick "Open Log",
 *      paste this whole file, Execute.
 *   4. Send back every line beginning READY.
 *
 * If step 1 is not possible, leave the list as it is: the standard names are tried, and the
 * report will say plainly that nothing was found, which is itself the answer.
 */

List<String> UNIFIED_DMOS = new List<String>{
    'UnifiedIndividual__dlm'
    // , 'apj_UnifiedIndividualApx1__dlm'
};

// ---------------------------------------------------------------- data spaces and rulesets

Map<Id, String> spaceById = new Map<Id, String>();
try {
    for (DataSpace space : [SELECT Id, DataSpaceApiName FROM DataSpace LIMIT 200]) {
        spaceById.put(space.Id, space.DataSpaceApiName);
    }
    System.debug('READY data spaces: ' + String.join(spaceById.values(), ', '));
} catch (Exception e) {
    System.debug('READY data spaces UNREADABLE: ' + e.getMessage());
}

try {
    for (IdentityResolution r : [
        SELECT Name, Suffix, DataSpaceId, LastRunStatus
        FROM IdentityResolution
        LIMIT 200
    ]) {
        System.debug(
            'READY ruleset "' + r.Name + '" suffix=' + (r.Suffix == null ? '(none)' : r.Suffix) +
            ' space=' + spaceById.get(r.DataSpaceId) + ' lastRun=' + r.LastRunStatus
        );
    }
} catch (Exception e) {
    System.debug('READY rulesets UNREADABLE: ' + e.getMessage());
}

// ---------------------------------------------------------------- naming per ruleset

// Mirrors how the app derives names, so a mismatch here is a mismatch in the app.
Pattern boundName = Pattern.compile('(?i)^((?:[A-Za-z0-9]+_)+)?Unified(.*?)Individual(.*?)__dlm$');

for (String bound : UNIFIED_DMOS) {
    String prefix = '', infix = '', suffix = '';
    Matcher parts = boundName.matcher(bound);
    if (parts.matches()) {
        prefix = parts.group(1) == null ? '' : parts.group(1);
        infix = parts.group(2) == null ? '' : parts.group(2);
        suffix = parts.group(3) == null ? '' : parts.group(3);
        System.debug(
            'READY --- ' + bound + ' | prefix="' + prefix + '" namespace="' + infix +
            '" ruleset="' + suffix + '"'
        );
    } else {
        System.debug(
            'READY --- ' + bound + ' | NAME NOT RECOGNISED. The app expects ' +
            '<prefix>Unified<namespace>Individual<ruleset>__dlm. Send this name back.'
        );
        continue;
    }

    List<String> expected = new List<String>{ bound };
    for (String entity : new List<String>{
        'Individual', 'ContactPointEmail', 'ContactPointPhone', 'ContactPointAddress'
    }) {
        if (entity != 'Individual') {
            expected.add(prefix + 'Unified' + infix + entity + suffix + '__dlm');
        }
        expected.add(prefix + 'UnifiedLink' + infix + entity + suffix + '__dlm');
        expected.add(prefix + entity + 'IdentityLink__dlm');
    }
    for (String standard : new List<String>{
        'ssot__Individual__dlm', 'ssot__ContactPointEmail__dlm', 'ssot__ContactPointPhone__dlm',
        'ssot__ContactPointAddress__dlm', 'ssot__EmailEngagement__dlm',
        'ssot__WebsiteEngagement__dlm', 'ssot__SalesOrder__dlm'
    }) {
        expected.add(String.isBlank(prefix) ? standard : prefix + standard.replace('ssot__', ''));
        if (String.isNotBlank(prefix)) {
            expected.add(standard);
        }
    }

    for (String name : expected) {
        try {
            Map<String, Schema.SObjectField> fields = Schema.describeSObjects(
                new List<String>{ name }
            )[0].fields.getMap();

            Boolean namespaced = false;
            for (String f : fields.keySet()) {
                if (f.startsWith('ssot__')) {
                    namespaced = true;
                    break;
                }
            }

            Integer rows = -1;
            try {
                rows = Database.countQuery('SELECT COUNT() FROM ' + name);
            } catch (Exception e) {
                rows = -1;
            }

            System.debug(
                'READY   present ' + name + ' | fields=' + fields.size() +
                ' | namespace=' + (namespaced ? 'ssot__' : 'none') +
                ' | rows=' + (rows < 0 ? 'unreadable' : String.valueOf(rows))
            );
        } catch (Exception e) {
            System.debug('READY   absent  ' + name);
        }
    }
}

System.debug('READY done. Send back every line beginning READY.');
