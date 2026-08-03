import { LightningElement, api } from 'lwc';
import { resolvePageContext } from 'c/dcPageContext';

/**
 * The unified profile layout, shared by the custom explorer app and by the CDP record page
 * (through an Aura wrapper, since LWC has no target for that page type).
 */
export default class UnifiedProfileView extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api insightApiNames;

    /**
     * Resolved once here and handed to every panel, so the whole page reads the same ruleset.
     * A CDP record page supplies no record context, so both values come from the URL and the
     * ruleset follows whichever Unified Individual DMO is being viewed.
     */
    effectiveRecordId;
    effectiveObject;

    connectedCallback() {
        const context = resolvePageContext(this);
        this.effectiveRecordId = context.recordId;
        this.effectiveObject = context.objectApiName;
    }

    /** Fetched up front; the timelines reveal the first ten and keep the rest behind an expander. */
    get engagementRows() {
        return 50;
    }

    get orderRows() {
        return 25;
    }

    get initialRows() {
        return 10;
    }

    /**
     * Segments are paged rather than expanded, since a profile can sit in hundreds. Five keeps
     * the card short; the reader can raise it from the picker in its header.
     */
    get segmentPageSize() {
        return 5;
    }

    get explorerPageSize() {
        return 5;
    }
}
