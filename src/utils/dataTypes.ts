import { AddressLike } from "ethers";

export interface SafeProtocolAction {
    to: AddressLike;
    value: bigint;
    data: string;
}

export interface SafeTransaction {
    actions: SafeProtocolAction[];
    nonce: bigint;
    metadataHash: Uint8Array | string;
}

export interface SafeRootAccess {
    action: SafeProtocolAction;
    nonce: bigint;
    metadataHash: Uint8Array | string;
}
