// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.5;
pragma experimental ABIEncoderV2;

import {DistributionTypes} from '../libraries/DistributionTypes.sol';

interface IHipoDistributionManager {

    function configureAssets(
        DistributionTypes.AssetConfigInput[] calldata assetsConfigInput
        ) external;
}
