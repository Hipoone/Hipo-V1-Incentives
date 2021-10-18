// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.7.5;
pragma experimental ABIEncoderV2;

import {DistributionTypes} from '../libraries/DistributionTypes.sol';
import {SafeMath} from '../dependencies/openzeppelin/contracts/SafeMath.sol';

contract HipoDistributionManager {

    using SafeMath for uint256;

    struct AssetData {
        uint128 emissionPerSecond;
        uint128 lastUpdateTimestamp;
        uint256 index;
        mapping(address => uint256) users;
    }

    mapping(address => AssetData) public assets;

    uint256 public immutable DISTRIBUTION_END;

    address public immutable EMISSION_MANAGER;

    uint8 public constant PRECISION = 18;

    event AssetIndexUpdated(address indexed asset, uint256 index);
    event UserIndexUpdated(address indexed user, address indexed asset, uint256 index);
    event AssetConfigUpdated(address indexed asset, uint256 emission);

    constructor (address emissionManager, uint256 distributionDuration) {
        DISTRIBUTION_END = block.timestamp.add(distributionDuration);
        EMISSION_MANAGER = emissionManager;
    }

    function configureAssets(DistributionTypes.AssetConfigInput[] calldata assetsConfigInput)
        external
        {
            require(msg.sender == EMISSION_MANAGER, 'ONLY_EMISSION_MANAGER');

            for (uint256 i = 0; i < assetsConfigInput.length; i++) {
                AssetData storage assetConfig = assets[assetsConfigInput[i].underlyingAsset];

                _updateAssetStateInternal(
                    assetsConfigInput[i].underlyingAsset,
                    assetConfig,
                    assetsConfigInput[i].totalStaked
                    );

                assetConfig.emissionPerSecond = assetsConfigInput[i].emissionPerSecond;

                emit AssetConfigUpdated(
                    assetsConfigInput[i].underlyingAsset,
                    assetsConfigInput[i].emissionPerSecond
                    );
            }
        }

    function _updateAssetStateInternal(
        address underlyingAsset,
        AssetData storage assetConfig,
        uint256 totalStaked
        ) internal returns(uint256) {
            uint256 oldIndex = assetConfig.index;
            uint128 lastUpdateTimestamp = assetConfig.lastUpdateTimestamp;

            if (block.timestamp == lastUpdateTimestamp) {
                return oldIndex;
            }

            uint256 newIndex =
                _getAssetIndex(oldIndex, assetConfig.emissionPerSecond, lastUpdateTimestamp, totalStaked);

            if (newIndex != oldIndex) {
                assetConfig.index = newIndex;
                emit AssetIndexUpdated(underlyingAsset, newIndex);
            }

            assetConfig.lastUpdateTimestamp = uint128(block.timestamp);

            return newIndex;
        }

    function _getAssetIndex(
        uint256 currentIndex,
        uint256 emissionPerSecond,
        uint128 lastUpdateTimestamp,
        uint256 totalBalance
        ) internal view returns (uint256) {
            if(
                emissionPerSecond == 0 ||
                totalBalance == 0 ||
                lastUpdateTimestamp == block.timestamp ||
                lastUpdateTimestamp >= DISTRIBUTION_END
                ) {
                    return currentIndex;
                }

            uint256 currentTimestamp =
                block.timestamp > DISTRIBUTION_END ? DISTRIBUTION_END : block.timestamp;
            uint256 timeDelta = currentTimestamp.sub(lastUpdateTimestamp);

            return
                emissionPerSecond.mul(timeDelta).mul(10**uint256(PRECISION)).div(totalBalance)
                                 .add(currentIndex);
        }

    function _updateUserAssetInternal(
        address user,
        address asset,
        uint256 stakedByUser,
        uint256 totalStaked
        ) internal returns (uint256) {
            AssetData storage assetData = assets[asset];
            uint256 userIndex = assetData.users[user];
            uint256 accrueRewards = 0;

            uint256 newIndex = _updateAssetStateInternal(asset, assetData, totalStaked);

            if (userIndex != newIndex) {
                if (stakedByUser !=0) {
                    accrueRewards = _getRewards(stakedByUser, newIndex, userIndex);
                }

                assetData.users[user] = newIndex;
                emit UserIndexUpdated(user, asset, newIndex);
            }

            return accrueRewards;
        }

    function _getRewards(
        uint256 principalUserBalance,
        uint256 reserveIndex,
        uint256 userIndex
        ) internal pure returns (uint256) {
            return principalUserBalance.mul(reserveIndex.sub(userIndex)).div(10**uint256(PRECISION));
        }

    function _claimRewards(address user, DistributionTypes.UserStakeInput[] memory stakes)
        internal
        returns(uint256) {
            uint256 accrueRewards = 0;

            for (uint256 i = 0; i < stakes.length; i++) {
                accrueRewards = accrueRewards.add(
                    _updateUserAssetInternal(
                        user,
                        stakes[i].underlyingAsset,
                        stakes[i].stakedByUser,
                        stakes[i].totalStaked
                        )
                    );
            }

            return accrueRewards;
        }

    function getUserAssetData(address user, address asset) public view returns(uint256) {
        return assets[asset].users[user];
    }

    function _getUnclaimedRewards(
        address user,
        DistributionTypes.UserStakeInput[] memory stakes
        )
        internal
        view
        returns (uint256) {

            uint256 accrueRewards = 0;
            for (uint256 i = 0; i < stakes.length; i++) {
                AssetData storage assetConfig = assets[stakes[i].underlyingAsset];
                uint256 assetIndex =
                    _getAssetIndex(
                        assetConfig.index,
                        assetConfig.emissionPerSecond,
                        assetConfig.lastUpdateTimestamp,
                        stakes[i].totalStaked
                        );

            accrueRewards = accrueRewards.add(
                _getRewards(stakes[i].stakedByUser, assetIndex, assetConfig.users[user]));
            }

            return accrueRewards;
        }
}
