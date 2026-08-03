import { LightningElement, api, track } from 'lwc';
import getSegments from '@salesforce/apex/UnifiedSegmentController.getSegments';
import { resolvePageContext } from 'c/dcPageContext';

export default class UnifiedSegmentPanel extends LightningElement {
    @api recordId;
    @api objectApiName;

    /** Rows per page to open with. A profile can sit in hundreds of segments, so the list is paged. */
    @api pageSize = 5;

    /** Reader's own choice, which outranks the page size set in App Builder once they make one. */
    chosenSize;

    @track segments = [];
    truncated = false;
    notice;
    error;
    loading = true;
    page = 1;

    connectedCallback() {
        getSegments(resolvePageContext(this))
            .then((data) => {
                this.segments = data?.segments || [];
                this.truncated = data?.truncated || false;
                this.notice = data?.notice;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load segment membership.';
            })
            .finally(() => {
                this.loading = false;
            });
    }

    get size() {
        const requested = parseInt(this.chosenSize || this.pageSize, 10);
        return requested > 0 ? requested : 5;
    }

    get pageSizeOptions() {
        return [5, 10, 25].map((value) => ({
            value: String(value),
            label: `${value} per page`,
            checked: value === this.size
        }));
    }

    get pageSizeLabel() {
        return `${this.size} per page`;
    }

    handlePageSize(event) {
        this.chosenSize = parseInt(event.detail.value, 10);
        this.page = 1;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.segments.length / this.size));
    }

    get visibleSegments() {
        const start = (this.page - 1) * this.size;
        return this.segments.slice(start, start + this.size).map((s) => ({
            ...s,
            key: s.segmentId,
            statusClass: `upe-status upe-status_${(s.status || 'unknown').toLowerCase().split(' ')[0]}`,
            publishTypeLabel: s.publishType ? `${s.publishType} publish` : null,
            memberCountLabel:
                s.memberCount === null || s.memberCount === undefined
                    ? null
                    : `${s.memberCount.toLocaleString()} members`
        }));
    }

    get hasSegments() {
        return this.segments.length > 0;
    }

    get isEmpty() {
        return !this.loading && !this.error && this.segments.length === 0;
    }

    get emptyMessage() {
        return this.notice || 'This profile is not a member of any published segment.';
    }

    get rangeLabel() {
        const total = this.segments.length;
        const start = (this.page - 1) * this.size + 1;
        const end = Math.min(this.page * this.size, total);
        return `${start}\u2013${end} of ${total} ${total === 1 ? 'segment' : 'segments'}`;
    }

    get showPager() {
        return this.segments.length > this.size;
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
