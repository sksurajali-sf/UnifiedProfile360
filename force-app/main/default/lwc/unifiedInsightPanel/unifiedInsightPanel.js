import { LightningElement, api } from 'lwc';
import getInsightOptions from '@salesforce/apex/UnifiedInsightController.getInsightOptions';
import getInsightData from '@salesforce/apex/UnifiedInsightController.getInsightData';
import { resolvePageContext } from 'c/dcPageContext';

export default class UnifiedInsightPanel extends LightningElement {
    @api recordId;
    @api objectApiName;

    /** Fallback only. The picker is normally built from the org's insight catalogue. */
    @api insightApiNames = 'Lifetime_Purchase_Count__cio,Total_Visits__cio,Cg_Monthly_Count__cio';

    options = [];
    selected;
    result;
    error;
    loadingOptions = true;
    loadingData = false;

    connectedCallback() {
        getInsightOptions({
            insightApiNames: this.insightApiNames,
            objectApiName: resolvePageContext(this).objectApiName
        })
            .then((data) => {
                this.options = (data || []).map((o) => ({ label: o.label, value: o.apiName }));
                if (this.options.length) {
                    this.selected = this.options[0].value;
                    this.fetchInsight();
                }
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to list calculated insights.';
            })
            .finally(() => {
                this.loadingOptions = false;
            });
    }

    fetchInsight() {
        if (!this.selected) {
            return;
        }
        this.loadingData = true;
        this.error = undefined;

        getInsightData({
            ciApiName: this.selected,
            ...resolvePageContext(this)
        })
            .then((data) => {
                this.result = data;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load this calculated insight.';
                this.result = undefined;
            })
            .finally(() => {
                this.loadingData = false;
            });
    }

    handleChange(event) {
        this.selected = event.detail.value;
        this.fetchInsight();
    }

    get hasOptions() {
        return this.options.length > 0;
    }

    get noOptions() {
        return !this.loadingOptions && this.options.length === 0;
    }

    /**
     * An insight keyed only by the profile returns one row. One that also carries dimensions
     * returns a row per combination, so each is rendered with its dimensions above the measures.
     */
    get viewRows() {
        return (this.result?.rows || []).map((row, index) => ({
            key: row.key || `row-${index}`,
            hasDimensions: (row.dimensions || []).length > 0,
            dimensions: (row.dimensions || []).map((d) => ({ ...d, key: d.apiName })),
            measures: (row.measures || []).map((m) => ({ ...m, key: m.apiName }))
        }));
    }

    get hasData() {
        return this.viewRows.length > 0;
    }

    /** Only surfaced once the request has settled, so it never flashes during loading. */
    get emptyMessage() {
        if (this.loadingData || this.hasData) {
            return null;
        }
        return this.result?.message || null;
    }

    get keyFieldLabel() {
        return this.result?.keyField;
    }

    get rowCountLabel() {
        const count = this.viewRows.length;
        return count > 1 ? `${count} groups` : null;
    }
}
