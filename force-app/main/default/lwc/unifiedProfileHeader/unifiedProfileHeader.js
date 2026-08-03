import { LightningElement, api } from 'lwc';
import getProfileHeader from '@salesforce/apex/UnifiedProfileController.getProfileHeader';
import { resolvePageContext } from 'c/dcPageContext';

export default class UnifiedProfileHeader extends LightningElement {
    @api recordId;
    @api objectApiName;

    /** Name of the tool, set here so a page can rebrand the whole experience from one place. */
    @api productName = 'Unified Profile 360';

    header;
    error;
    loading = true;

    connectedCallback() {
        const context = resolvePageContext(this);

        getProfileHeader(context)
            .then((data) => {
                this.header = data;
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load this unified profile.';
                this.header = undefined;
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get displayName() {
        if (!this.header) {
            return '';
        }
        const { personName, firstName, lastName } = this.header;
        if (personName) {
            return personName;
        }
        return [firstName, lastName].filter(Boolean).join(' ') || 'Unified Individual';
    }

    get initials() {
        const name = this.displayName.trim();
        if (!name) {
            return '?';
        }
        const parts = name.split(/\s+/);
        const first = parts[0]?.charAt(0) || '';
        const second = parts.length > 1 ? parts[parts.length - 1].charAt(0) : '';
        return (first + second).toUpperCase();
    }

    /**
     * Winner attributes reconciled by the identity resolution ruleset. Only fields that
     * actually exist on the unified DMOs are listed; there is no Address Line 2.
     */
    get fields() {
        if (!this.header) {
            return [];
        }
        return [
            { key: 'firstName', label: 'First Name', value: this.header.firstName },
            { key: 'lastName', label: 'Last Name', value: this.header.lastName },
            { key: 'unifiedId', label: 'Unified Individual Id', value: this.header.unifiedId, mono: true },
            { key: 'email', label: 'Unified Email (Winner)', value: this.header.email },
            { key: 'phone', label: 'Unified Phone (Winner)', value: this.header.phone },
            { key: 'addressLine1', label: 'Address Line 1', value: this.header.addressLine1 },
            { key: 'city', label: 'City', value: this.header.city },
            { key: 'stateProvince', label: 'State/Province', value: this.header.stateProvince },
            { key: 'postalCode', label: 'Postal Code', value: this.header.postalCode },
            { key: 'country', label: 'Country', value: this.header.country }
        ].map((f) => ({
            ...f,
            display: f.value || '—',
            valueClass: f.mono
                ? 'slds-text-body_small upe-value upe-value_mono'
                : 'slds-text-body_regular upe-value'
        }));
    }

    /**
     * When identity resolution last finished, falling back to the unified record's own date in
     * an org that does not expose the ruleset.
     */
    get resolutionDate() {
        return this.header?.resolutionLastRun || this.header?.lastModified;
    }

    get hasResolutionDate() {
        return !!this.resolutionDate;
    }

    get resolutionDateLabel() {
        return this.header?.resolutionLastRun ? 'Identity Resolution Last Run' : 'Record Last Modified';
    }

    get resolutionDateTitle() {
        if (!this.header?.resolutionLastRun) {
            return 'This unified record was last rewritten on this date.';
        }
        const name = this.header.resolutionName || 'This ruleset';
        const status = this.header.resolutionRunStatus;
        const outcome = status && status.toUpperCase() !== 'SUCCESS' ? ` Latest run status: ${status}.` : '';
        return `${name} last completed successfully on this date.${outcome}`;
    }

    get rulesetLabel() {
        return this.header?.rulesetDmo;
    }
}
