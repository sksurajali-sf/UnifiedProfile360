import { LightningElement, api } from 'lwc';
import getOrderTimeline from '@salesforce/apex/UnifiedProfileController.getOrderTimeline';
import { resolvePageContext } from 'c/dcPageContext';

const STATUS_THEME = {
    delivered: 'upe-status upe-status_success',
    shipped: 'upe-status upe-status_info',
    processing: 'upe-status upe-status_warning',
    pending: 'upe-status upe-status_warning',
    cancelled: 'upe-status upe-status_error'
};

const DEFAULT_PAGE_SIZE = 10;
const ALL = 'All';
const NO_STATUS = 'No status';

/** Orders with nothing in the status column still need a name to be filtered by. */
function statusOf(order) {
    const status = (order.status || '').trim();
    return status || NO_STATUS;
}

export default class UnifiedOrderTimeline extends LightningElement {
    @api recordId;
    @api objectApiName;

    /** Orders fetched from Data Cloud. Everything beyond initialRows sits behind the expander. */
    @api maxRows = 25;
    @api initialRows = DEFAULT_PAGE_SIZE;

    orders = [];
    error;
    loading = true;
    activeStatus = ALL;
    expanded = false;

    connectedCallback() {
        this.loadOrders();
    }

    loadOrders() {
        getOrderTimeline({
            ...resolvePageContext(this),
            maxRows: this.maxRows
        })
            .then((data) => {
                this.orders = data || [];
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error?.body?.message || 'Unable to load order history.';
                this.orders = [];
            })
            .finally(() => {
                this.loading = false;
            });
    }

    /** Design attributes arrive as strings, so the page size is coerced before it is used. */
    get pageSize() {
        return Number(this.initialRows) || DEFAULT_PAGE_SIZE;
    }

    /** Already sorted newest-first by Apex; filtering preserves that order. */
    get filteredOrders() {
        return this.activeStatus === ALL
            ? this.orders
            : this.orders.filter((o) => statusOf(o) === this.activeStatus);
    }

    /** The statuses this profile's orders actually carry, counted. */
    get statusOptions() {
        const counts = new Map();
        this.orders.forEach((o) => {
            const status = statusOf(o);
            counts.set(status, (counts.get(status) || 0) + 1);
        });

        const options = [...counts.keys()].sort((a, b) => a.localeCompare(b)).map((status) => ({
            value: status,
            label: `${status} (${counts.get(status)})`,
            checked: this.activeStatus === status
        }));

        return [
            {
                value: ALL,
                label: `All statuses (${this.orders.length})`,
                checked: this.activeStatus === ALL
            },
            ...options
        ];
    }

    get statusLabel() {
        return this.activeStatus === ALL ? 'All statuses' : this.activeStatus;
    }

    /** Reads as a plain control until it is narrowing the list, then it stands out. */
    get statusVariant() {
        return this.activeStatus === ALL ? 'border-filled' : 'brand';
    }

    /** Nothing to narrow when every order shares one status. */
    get hasStatusFilter() {
        return new Set(this.orders.map(statusOf)).size > 1;
    }

    get visibleOrders() {
        const filtered = this.filteredOrders;
        const shown = this.expanded ? filtered : filtered.slice(0, this.pageSize);

        return shown.map((order, index) => ({
            ...order,
            key: order.orderNumber || `order-${index}`,
            statusClass: STATUS_THEME[(order.status || '').toLowerCase()] || 'upe-status',
            hasAmount: order.totalAmount !== null && order.totalAmount !== undefined,
            hasDate: !!order.orderDate,
            currencyCode: order.currencyCode || 'USD'
        }));
    }

    /**
     * Totals every order in view, not just the ones on screen, and keeps currencies apart.
     * Orders here arrive in whatever currency they were placed in, so a single figure would
     * be adding pounds to rupees. Filtering by status re-totals, so the headline figure always
     * describes the orders the reader can see.
     */
    get currencyTotals() {
        const totals = new Map();

        for (const order of this.filteredOrders) {
            if (order.totalAmount === null || order.totalAmount === undefined) {
                continue;
            }
            const code = order.currencyCode || 'USD';
            totals.set(code, (totals.get(code) || 0) + order.totalAmount);
        }

        return [...totals.entries()]
            .map(([currencyCode, amount]) => ({ key: currencyCode, currencyCode, amount }))
            .sort((a, b) => b.amount - a.amount);
    }

    get hasAnyAmount() {
        return this.currencyTotals.length > 0;
    }

    get orderCountLabel() {
        const n = this.orders.length;
        return n === 1 ? '1 order' : `${n} orders`;
    }

    /** Says how much of the history in view the total actually covers. */
    get totalScopeLabel() {
        const inView = this.filteredOrders;
        const priced = inView.filter(
            (o) => o.totalAmount !== null && o.totalAmount !== undefined
        ).length;
        const noun = inView.length === 1 ? 'order' : 'orders';

        if (priced === inView.length) {
            return `across ${inView.length} ${noun}`;
        }
        return `across ${priced} of ${inView.length} ${noun}`;
    }

    get isExpandable() {
        return this.filteredOrders.length > this.pageSize;
    }

    get toggleLabel() {
        if (this.expanded) {
            return 'Show less';
        }
        return `Show ${this.filteredOrders.length - this.pageSize} more`;
    }

    get toggleIcon() {
        return this.expanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    get isEmpty() {
        return !this.loading && !this.error && this.orders.length === 0;
    }

    /** The filter narrowed the list to nothing, which is not the same as having no orders. */
    get isFilteredEmpty() {
        return this.orders.length > 0 && this.filteredOrders.length === 0;
    }

    get filteredEmptyMessage() {
        return `No ${this.activeStatus} orders for this profile.`;
    }

    get hasVisibleOrders() {
        return this.filteredOrders.length > 0;
    }

    handleStatus(event) {
        this.activeStatus = event.detail.value;
        // A new filter means a new row count, so the list starts collapsed again.
        this.expanded = false;
    }

    handleToggle() {
        this.expanded = !this.expanded;
    }
}
