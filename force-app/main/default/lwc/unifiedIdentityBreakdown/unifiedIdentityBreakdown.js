import { LightningElement, api } from 'lwc';
import getIndividualBreakdown from '@salesforce/apex/UnifiedProfileController.getIndividualBreakdown';
import getContactPointBreakdown from '@salesforce/apex/UnifiedProfileController.getContactPointBreakdown';
import { resolvePageContext } from 'c/dcPageContext';

const SECTIONS = [
    { key: 'individuals', label: 'Individuals', icon: 'standard:people', cpType: null, expanded: true },
    { key: 'emails', label: 'All Emails', icon: 'standard:email', cpType: 'Email', expanded: true },
    { key: 'phones', label: 'All Phone Numbers', icon: 'standard:call', cpType: 'Phone', expanded: true },
    { key: 'addresses', label: 'All Addresses', icon: 'standard:address', cpType: 'Address', expanded: true }
];

export default class UnifiedIdentityBreakdown extends LightningElement {
    @api recordId;
    @api objectApiName;

    sections = SECTIONS.map((s) => ({ ...s, loading: true, rows: [], totalCount: 0, winnerValue: null }));

    connectedCallback() {
        this.load();
    }

    load() {
        const args = resolvePageContext(this);

        // Fired together so each section paints as soon as its own DMO query returns.
        SECTIONS.forEach((section) => {
            const request = section.cpType
                ? getContactPointBreakdown({ ...args, cpType: section.cpType })
                : getIndividualBreakdown(args);

            request
                .then((data) => this.applySection(section.key, data, null))
                .catch((error) => this.applySection(section.key, null, error));
        });
    }

    applySection(key, data, error) {
        this.sections = this.sections.map((section) => {
            if (section.key !== key) {
                return section;
            }
            return {
                ...section,
                loading: false,
                error: error ? error?.body?.message || 'Unable to load this section.' : null,
                winnerValue: data?.winnerValue || null,
                totalCount: data?.totalCount || 0,
                winnerMatchCount: data?.winnerMatchCount || 0,
                winnerSources: data?.winnerSources || [],
                winnerLatestDate: data?.winnerLatestDate,
                winnerEarliestDate: data?.winnerEarliestDate,
                winnerBasis: data?.winnerBasis || null,
                unifiedValueCount: data?.unifiedValueCount || 0,
                rows: (data?.rows || []).map((row, index) => ({
                    ...row,
                    key: `${key}-${row.sourceRecordId || index}`,
                    displayValue: row.value || '—',
                    // Green marks the one record the unified value is attributed to. Rows that merely
                    // repeat that value are counted in the rationale instead of being highlighted.
                    rowClass: row.isWinner ? 'upe-row upe-row_winner' : 'upe-row'
                }))
            };
        });
    }

    get viewSections() {
        return this.sections.map((section) => {
            const winnerRow = section.rows.find((r) => r.isWinner);
            return {
            ...section,
            hasRows: section.rows.length > 0,
            isEmpty: !section.loading && !section.error && section.rows.length === 0,
            countLabel: section.totalCount === 1 ? '1 record' : `${section.totalCount} records`,
            winnerDisplay: section.winnerValue || null,
            iconToggle: section.expanded ? 'utility:chevrondown' : 'utility:chevronright',
            bodyClass: section.expanded ? 'upe-section__body' : 'slds-hide',
            valueHeader: section.key === 'individuals' ? 'Name' : 'Value',
            winnerLabel:
                section.key === 'individuals'
                    ? 'Winning value: the reconciled name on the unified record'
                    : `Winning value: ${section.winnerValue}`,
            agreementLabel: `${section.winnerMatchCount || 0} of ${section.totalCount || 0} contributing records carry this value`,
            sourcesLabel: (section.winnerSources || []).join(', '),
            hasSources: (section.winnerSources || []).length > 0,
            // Reconciliation can keep more than one value of a type, and only the primary is badged.
            hasOtherValues: section.unifiedValueCount > 1,
            otherValuesLabel: `The profile also holds ${section.unifiedValueCount - 1} other unified ${
                section.unifiedValueCount === 2 ? 'value' : 'values'
            } of this type, listed below without a winner flag`,
            /*
             * The green row's own date, so the rationale and the Created column never quote
             * different days. Naming the most recent contributing record here instead read as
             * the reason the winner won, even when a later record lost to attribution.
             */
            winnerLinkedDate: winnerRow?.createdDate,
            winnerRecordId: winnerRow?.sourceRecordId,
            popoverClass: section.showInfo ? 'upe-popover' : 'slds-hide'
            };
        });
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this.sections = this.sections.map((section) =>
            section.key === key ? { ...section, expanded: !section.expanded } : section
        );
    }

    handleInfo(event) {
        // Stop the click from also collapsing the section behind the popover.
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        this.sections = this.sections.map((section) =>
            section.key === key
                ? { ...section, showInfo: !section.showInfo }
                : { ...section, showInfo: false }
        );
    }
}
