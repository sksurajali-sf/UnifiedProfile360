import { LightningElement, api } from 'lwc';

export default class ProfileExplorerDetail extends LightningElement {
    @api unifiedId;
    @api dmoApiName;
    @api profileName;
    @api insightApiNames;

    handleBack() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}
