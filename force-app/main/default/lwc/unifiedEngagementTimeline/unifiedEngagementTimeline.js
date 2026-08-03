import { LightningElement, api } from 'lwc';
import getEngagementTimeline from '@salesforce/apex/UnifiedProfileController.getEngagementTimeline';
import { resolvePageContext } from 'c/dcPageContext';

const CHANNEL_THEME = {
    Email: 'upe-node upe-node_email',
    Web: 'upe-node upe-node_web'
};

const DEFAULT_PAGE_SIZE = 10;
const ALL = 'All';

export default class UnifiedEngagementTimeline extends LightningElement {
    @api recordId;
    @api objectApiName;

    /** Rows fetched from Data Cloud. Everything beyond initialRows stays behind the expander. */
    @api maxRows = 50;
    @api initialRows = DEFAULT_PAGE_SIZE;

    events = [];
    error;
    loading = true;
    activeChannel = ALL;
    activeStatus = ALL;
    expanded = false;

    connectedCallback() {
        this.loadEvents();
    }

    loadEvents() {
        getEngagementTimeline({
            ...resolvePageContext(this),
            maxRows: this.maxRows
        })
            .then((data) => {
                this.events = data || [];
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load engagement history.';
                this.events = [];
            })
            .finally(() => {
                this.loading = false;
            });
    }

    /** Design attributes arrive as strings, so the page size is coerced before it is used. */
    get pageSize() {
        return Number(this.initialRows) || DEFAULT_PAGE_SIZE;
    }

    /** What the chosen channel covers, and so what the status dropdown can offer. */
    get scopedEvents() {
        return this.activeChannel === ALL
            ? this.events
            : this.events.filter((e) => e.channel === this.activeChannel);
    }

    /** Already sorted newest-first by Apex; filtering preserves that order. */
    get filteredEvents() {
        return this.activeStatus === ALL
            ? this.scopedEvents
            : this.scopedEvents.filter((e) => e.eventType === this.activeStatus);
    }

    get visibleEvents() {
        const filtered = this.filteredEvents;
        const shown = this.expanded ? filtered : filtered.slice(0, this.pageSize);

        return shown.map((event, index) => ({
            ...event,
            key: event.id || `event-${index}`,
            nodeClass: CHANNEL_THEME[event.channel] || 'upe-node',
            hasCampaign: !!event.campaignName,
            hasDetail: !!event.detail
        }));
    }

    /** Counts follow the status filter, so the tabs always add up to what is on screen. */
    get channels() {
        const matching = this.events.filter(
            (e) => this.activeStatus === ALL || e.eventType === this.activeStatus
        );
        const counts = matching.reduce((acc, e) => {
            acc[e.channel] = (acc[e.channel] || 0) + 1;
            return acc;
        }, {});

        return [ALL, 'Email', 'Web'].map((name) => {
            const count = name === ALL ? matching.length : counts[name] || 0;
            return {
                name,
                label: `${name} (${count})`,
                variant: this.activeChannel === name ? 'brand' : 'neutral'
            };
        });
    }

    /** The statuses the current channel actually has, newest naming straight from the events. */
    get statusOptions() {
        const counts = new Map();
        this.scopedEvents.forEach((e) => {
            if (e.eventType) {
                counts.set(e.eventType, (counts.get(e.eventType) || 0) + 1);
            }
        });

        const options = [...counts.keys()].sort((a, b) => a.localeCompare(b)).map((status) => ({
            value: status,
            label: `${status} (${counts.get(status)})`,
            checked: this.activeStatus === status
        }));

        return [
            {
                value: ALL,
                label: `All statuses (${this.scopedEvents.length})`,
                checked: this.activeStatus === ALL
            },
            ...options
        ];
    }

    get statusLabel() {
        return this.activeStatus === ALL ? 'All statuses' : this.activeStatus;
    }

    /** Hidden rather than shown empty when a channel has nothing to filter. */
    get hasStatusFilter() {
        return this.scopedEvents.length > 0;
    }

    /** Reads as a plain control until it is narrowing the list, then it stands out. */
    get statusVariant() {
        return this.activeStatus === ALL ? 'border-filled' : 'brand';
    }

    get isExpandable() {
        return this.filteredEvents.length > this.pageSize;
    }

    get toggleLabel() {
        if (this.expanded) {
            return 'Show less';
        }
        return `Show ${this.filteredEvents.length - this.pageSize} more`;
    }

    get toggleIcon() {
        return this.expanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get isEmpty() {
        return !this.loading && !this.error && this.filteredEvents.length === 0;
    }

    get emptyMessage() {
        if (this.activeStatus !== ALL) {
            return `No ${this.activeStatus} events in this view.`;
        }
        return 'No engagement to display.';
    }

    get hasEvents() {
        return this.filteredEvents.length > 0;
    }

    handleChannel(event) {
        this.activeChannel = event.currentTarget.dataset.channel;
        // A new filter means a new row count, so the list starts collapsed again.
        this.expanded = false;

        // The status picked on the previous channel may not exist on this one.
        if (!this.scopedEvents.some((e) => e.eventType === this.activeStatus)) {
            this.activeStatus = ALL;
        }
    }

    handleStatus(event) {
        this.activeStatus = event.detail.value;
        this.expanded = false;
    }

    handleToggle() {
        this.expanded = !this.expanded;
    }
}
