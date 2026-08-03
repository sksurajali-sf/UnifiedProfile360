import { LightningElement, api, track } from 'lwc';
import getRelatedObjects from '@salesforce/apex/UnifiedDmoExplorerController.getRelatedObjects';
import describeObject from '@salesforce/apex/UnifiedDmoExplorerController.describeObject';
import search from '@salesforce/apex/UnifiedDmoExplorerController.search';
import { resolvePageContext } from 'c/dcPageContext';

const ROW_LIMIT = 100;

export default class UnifiedDataExplorer extends LightningElement {
    @api recordId;
    @api objectApiName;

    /** Rows per page in the results table. */
    @api pageSize = 5;

    @track objects = [];
    @track fields = [];
    @track selectedFields = [];
    @track columns = [];
    @track rows = [];

    selectedObject;
    keyColumn;
    orderedBy;
    truncated = false;
    notice;
    error;

    loadingObjects = true;
    loadingFields = false;
    searching = false;
    searched = false;
    page = 1;

    context;

    connectedCallback() {
        this.context = resolvePageContext(this);
        getRelatedObjects({ objectApiName: this.context.objectApiName })
            .then((data) => {
                this.objects = data || [];
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load related data model objects.';
            })
            .finally(() => {
                this.loadingObjects = false;
            });
    }

    // ------------------------------------------------------------------
    // Pickers
    // ------------------------------------------------------------------

    get objectOptions() {
        return this.objects.map((o) => ({
            label: o.category ? `${o.label} (${o.category})` : o.label,
            value: o.apiName,
            description: o.relationship
        }));
    }

    get fieldOptions() {
        return this.fields.map((f) => ({ label: f.label, value: f.apiName }));
    }

    /** Every field of the object is a candidate key, since ids turn up in unexpected columns. */
    get keyOptions() {
        return this.fields.map((f) => ({
            label: f.label,
            value: f.apiName,
            description: f.apiName
        }));
    }

    get objectPlaceholder() {
        return this.loadingObjects ? 'Loading objects\u2026' : 'Choose a data model object';
    }

    get fieldsDisabled() {
        return !this.selectedObject || this.loadingFields;
    }

    get searchDisabled() {
        return !this.selectedObject || !this.keyColumn || this.selectedFields.length === 0 || this.searching;
    }

    get fieldHelp() {
        if (!this.selectedObject) {
            return 'Pick an object first';
        }
        const chosen = this.selectedFields.length;
        if (chosen === 0) {
            return `No columns selected of ${this.fields.length} available`;
        }
        return `${chosen} of ${this.fields.length} columns selected`;
    }

    handleObject(event) {
        this.selectedObject = event.detail.value;
        this.fields = [];
        this.selectedFields = [];
        this.keyColumn = undefined;
        this.resetResults();
        this.loadingFields = true;
        this.error = undefined;

        describeObject({ dmoApiName: this.selectedObject, objectApiName: this.context.objectApiName })
            .then((detail) => {
                this.fields = detail?.fields || [];
                // The relationship already names the column that carries the individual reference.
                this.keyColumn = detail?.suggestedKey;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load fields for that object.';
            })
            .finally(() => {
                this.loadingFields = false;
            });
    }

    handleFields(event) {
        this.selectedFields = event.detail.value || [];
    }

    handleKeyColumn(event) {
        this.keyColumn = event.detail.value;
    }

    handleSearch() {
        if (this.searchDisabled) {
            return;
        }
        this.searching = true;
        this.error = undefined;
        this.resetResults();

        search({
            recordId: this.context.recordId,
            objectApiName: this.context.objectApiName,
            dmoApiName: this.selectedObject,
            fieldNames: this.selectedFields,
            keyColumn: this.keyColumn,
            rowLimit: ROW_LIMIT
        })
            .then((result) => {
                this.columns = result?.columns || [];
                this.rows = result?.rows || [];
                this.orderedBy = result?.orderedBy;
                this.truncated = result?.truncated || false;
                this.notice = result?.notice;
                this.searched = true;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'That search could not be run.';
            })
            .finally(() => {
                this.searching = false;
            });
    }

    resetResults() {
        this.columns = [];
        this.rows = [];
        this.orderedBy = undefined;
        this.truncated = false;
        this.notice = undefined;
        this.searched = false;
        this.page = 1;
    }

    // ------------------------------------------------------------------
    // Results
    // ------------------------------------------------------------------

    get size() {
        const requested = parseInt(this.pageSize, 10);
        return requested > 0 ? requested : 5;
    }

    get visibleRows() {
        const start = (this.page - 1) * this.size;
        // Walked by column rather than by cell, so a row always fills the headings it is under.
        return this.rows.slice(start, start + this.size).map((row) => ({
            key: row.key,
            cells: this.columns.map((column, index) => {
                const value = row.cells[index];
                const filled = value !== null && value !== undefined && value !== '';
                // Data Cloud sends numbers with a long decimal tail; dates arrive as ISO strings.
                const isDate = filled && (column.type === 'DATE_TIME' || column.type === 'DATE');
                const isNumber = filled && column.type === 'NUMBER' && !isNaN(Number(value));
                return {
                    key: `${row.key}-${index}`,
                    value,
                    isDate,
                    isNumber,
                    numberValue: isNumber ? Number(value) : undefined,
                    isText: !isDate && !isNumber,
                    display: filled ? value : '\u2014'
                };
            })
        }));
    }

    get hasResults() {
        return this.rows.length > 0;
    }

    get showEmptyState() {
        return this.searched && this.rows.length === 0;
    }

    get emptyMessage() {
        return this.notice || 'No records matched this profile on that column.';
    }

    get resultTitle() {
        const object = this.objects.find((o) => o.apiName === this.selectedObject);
        return object ? object.label : 'Records';
    }

    get orderNote() {
        return this.orderedBy ? `Newest first by ${this.orderedBy}` : 'In the order Data Cloud returned them';
    }

    get rangeLabel() {
        const total = this.rows.length;
        const start = (this.page - 1) * this.size + 1;
        const end = Math.min(this.page * this.size, total);
        return `${start}\u2013${end} of ${total} ${total === 1 ? 'record' : 'records'}`;
    }

    get truncationNote() {
        return `latest ${ROW_LIMIT} only`;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.rows.length / this.size));
    }

    get showPager() {
        return this.rows.length > this.size;
    }

    get onFirstPage() {
        return this.page <= 1;
    }

    get onLastPage() {
        return this.page >= this.totalPages;
    }

    handlePrevious() {
        if (this.page > 1) {
            this.page -= 1;
        }
    }

    handleNext() {
        if (this.page < this.totalPages) {
            this.page += 1;
        }
    }
}
