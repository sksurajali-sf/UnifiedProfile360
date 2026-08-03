import { LightningElement, api } from 'lwc';

/**
 * Single entry point for the custom Profile Explorer. It owns the search/detail state so the
 * whole experience lives in one component and works for every unified profile DMO, rather
 * than needing a Lightning page bound to each one.
 */
export default class ProfileExplorerApp extends LightningElement {
    @api headerTitle = 'Unified Profile 360';
    @api insightApiNames = 'Lifetime_Purchase_Count__cio,Total_Visits__cio,Cg_Monthly_Count__cio';

    selected;

    handleView(event) {
        const { unifiedId, dmoApiName, name } = event.detail;
        this.selected = { unifiedId, dmoApiName, name: name || 'Unified Profile' };
    }

    handleBack() {
        this.selected = undefined;
    }

    get showDetail() {
        return !!this.selected;
    }

    get selectedId() {
        return this.selected?.unifiedId;
    }

    get selectedDmo() {
        return this.selected?.dmoApiName;
    }

    get selectedName() {
        return this.selected?.name;
    }
}
