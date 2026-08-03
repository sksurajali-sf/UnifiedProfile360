import { LightningElement, track } from 'lwc';
import getDataSpaces from '@salesforce/apex/ProfileExplorerController.getDataSpaces';
import getProfileDmos from '@salesforce/apex/ProfileExplorerController.getProfileDmos';
import getAttributes from '@salesforce/apex/ProfileExplorerController.getAttributes';
import searchProfiles from '@salesforce/apex/ProfileExplorerController.searchProfiles';

export default class ProfileExplorerSearch extends LightningElement {
    @track dataSpaces = [];
    @track dmos = [];
    @track attributes = [];
    @track rows = [];

    dataSpace;
    dmo;
    attribute;
    searchTerm = '';

    loadingSpaces = true;
    loadingDmos = false;
    loadingAttributes = false;
    searching = false;
    hasSearched = false;

    message;
    error;
    truncated = false;
    matchedLabel;

    connectedCallback() {
        getDataSpaces()
            .then((spaces) => {
                this.dataSpaces = (spaces || []).map((s) => ({ label: s.label, value: s.apiName }));
                const preferred =
                    this.dataSpaces.find((s) => s.value === 'default') || this.dataSpaces[0];
                if (preferred) {
                    this.dataSpace = preferred.value;
                    this.loadDmos();
                }
            })
            .catch((e) => {
                this.error = this.readError(e, 'Unable to load data spaces.');
            })
            .finally(() => {
                this.loadingSpaces = false;
            });
    }

    loadDmos() {
        this.loadingDmos = true;
        this.dmo = undefined;
        this.attribute = undefined;
        this.attributes = [];
        this.resetResults();

        getProfileDmos({ dataSpaceApiName: this.dataSpace })
            .then((dmos) => {
                this.dmos = (dmos || []).map((d) => ({ label: d.label, value: d.apiName }));
                if (this.dmos.length) {
                    this.dmo = this.dmos[0].value;
                    this.loadAttributes();
                }
            })
            .catch((e) => {
                this.error = this.readError(e, 'Unable to load objects.');
            })
            .finally(() => {
                this.loadingDmos = false;
            });
    }

    loadAttributes() {
        this.loadingAttributes = true;
        this.attribute = undefined;
        this.resetResults();

        getAttributes({ dmoApiName: this.dmo })
            .then((attrs) => {
                this.attributes = attrs || [];
                const first = this.attributes[0];
                if (first) {
                    this.attribute = first.key;
                }
            })
            .catch((e) => {
                this.error = this.readError(e, 'Unable to load attributes.');
            })
            .finally(() => {
                this.loadingAttributes = false;
            });
    }

    /** Attributes are grouped so the picker mirrors the standard explorer's two sections. */
    get attributeGroups() {
        const groups = [];
        this.attributes.forEach((a) => {
            let group = groups.find((g) => g.label === a.groupLabel);
            if (!group) {
                group = { label: a.groupLabel, items: [] };
                groups.push(group);
            }
            group.items.push({ label: a.label, value: a.key });
        });
        return groups.map((g) => ({
            label: g.label,
            options: g.items
        }));
    }

    handleDataSpace(event) {
        this.dataSpace = event.detail.value;
        this.loadDmos();
    }

    handleDmo(event) {
        this.dmo = event.detail.value;
        this.loadAttributes();
    }

    handleAttribute(event) {
        this.attribute = event.detail.value;
        this.resetResults();
    }

    handleTerm(event) {
        this.searchTerm = event.target.value;
    }

    handleKey(event) {
        if (event.key === 'Enter') {
            this.runSearch();
        }
    }

    handleSearch() {
        this.runSearch();
    }

    handleClear() {
        this.searchTerm = '';
        this.resetResults();
    }

    runSearch() {
        if (!this.canSearch) {
            return;
        }
        this.searching = true;
        this.error = undefined;
        this.message = undefined;

        searchProfiles({
            dmoApiName: this.dmo,
            attributeKey: this.attribute,
            searchTerm: this.searchTerm
        })
            .then((result) => {
                this.rows = result?.rows || [];
                this.message = result?.message;
                this.truncated = result?.truncated || false;
                this.matchedLabel = result?.matchedLabel;
                this.hasSearched = true;
            })
            .catch((e) => {
                this.error = this.readError(e, 'Search failed.');
                this.rows = [];
            })
            .finally(() => {
                this.searching = false;
            });
    }

    handleView(event) {
        const { id, name } = event.currentTarget.dataset;
        this.dispatchEvent(
            new CustomEvent('view', {
                detail: { unifiedId: id, dmoApiName: this.dmo, name }
            })
        );
    }

    resetResults() {
        this.rows = [];
        this.message = undefined;
        this.truncated = false;
        this.hasSearched = false;
    }

    readError(e, fallback) {
        return e?.body?.message || e?.message || fallback;
    }

    get canSearch() {
        return !!this.dmo && !!this.attribute && (this.searchTerm || '').trim().length >= 2;
    }

    get searchDisabled() {
        return !this.canSearch || this.searching;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showEmptyState() {
        return this.hasSearched && !this.searching && this.rows.length === 0;
    }

    get showIdlePrompt() {
        return !this.hasSearched && !this.searching;
    }

    get resultCountLabel() {
        const count = this.rows.length;
        const base = count === 1 ? '1 profile' : `${count} profiles`;
        return this.truncated ? `${base} (showing first ${count})` : base;
    }

    get matchedColumnLabel() {
        return this.matchedLabel || 'Matched Value';
    }
}
