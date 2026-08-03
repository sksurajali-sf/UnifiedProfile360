const CDP_PATH = /\/lightning\/cdp\/([^/?#]+)\/([^/?#]+)/;
const DEFAULT_DMO = 'UnifiedIndividual__dlm';

/**
 * Works out which unified profile a panel is rendering.
 *
 * On a CDP record page the /lightning/cdp/<dmo>/<rowId>/view path is authoritative. The record
 * context handed to components there is unreliable: it is either empty or carries the page's
 * own entity rather than the ruleset being viewed, which silently pointed every panel at the
 * default Unified Individual DMO. Off that page the values passed in win, since the custom
 * explorer app supplies them from the search result. The row id becomes the 32-character
 * unified id in Apex.
 */
export function resolvePageContext(component) {
    const path = CDP_PATH.exec(window.location.pathname);
    if (path) {
        return {
            recordId: decodeURIComponent(path[2]),
            objectApiName: decodeURIComponent(path[1])
        };
    }

    return {
        recordId: component.recordId,
        objectApiName: component.objectApiName || DEFAULT_DMO
    };
}
