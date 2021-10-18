// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.7.5;
pragma experimental ABIEncoderV2;

import {HipoDistributionManager} from './HipoDistributionManager.sol';
import {DistributionTypes} from '../libraries/DistributionTypes.sol';
import {IERC20} from '../dependencies/openzeppelin/contracts/IERC20.sol';
import {IERC20Detailed} from '../dependencies/openzeppelin/contracts/IERC20Detailed.sol';
import {IHipoIncentivesController} from '../interfaces/IHipoIncentivesController.sol';
import {SafeMath} from '../dependencies/openzeppelin/contracts/SafeMath.sol';
import {VersionedInitializable} from '../utils/VersionedInitializable.sol';

contract HipoIncentivesController is HipoDistributionManager, VersionedInitializable, IHipoIncentivesController {

    using SafeMath for uint256;
    uint256 public constant REVISION = 1;

    mapping(address => uint256) internal _usersUnclaimedRewards;

    IERC20 public immutable REWARD_TOKEN;
    address public immutable REWARDS_VAULT;

    uint256 public constant HIPO_INCENTIVES_CONTROLLER_REVISION = 0x1;

    event RewardsAccrued(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed to, uint256 amount);

    constructor(
        address emissionManager,
        uint128 distributionDuration,
        IERC20 rewardToken,
        address rewardsVault
        ) HipoDistributionManager(emissionManager, distributionDuration) {
            REWARD_TOKEN = rewardToken;
            REWARDS_VAULT = rewardsVault;
        }

    function handleAction(
        address user,
        uint256 userBalance,
        uint256 totalSupply
        ) external override {
            uint256 accruedRewards = _updateUserAssetInternal(user, msg.sender, userBalance, totalSupply);
            if (accruedRewards != 0) {
                _usersUnclaimedRewards[user] = _usersUnclaimedRewards[user].add(accruedRewards);
                emit RewardsAccrued(user, accruedRewards);
            }
        }

    function getRewardsBalance(address[] calldata assets, address user)
        external
        view
        override
        returns (uint256) {
            uint256 unclaimedRewards = _usersUnclaimedRewards[user];

            DistributionTypes.UserStakeInput[] memory userState =
                new DistributionTypes.UserStakeInput[](assets.length);

            for (uint256 i = 0; i < assets.length; i++) {
                userState[i].underlyingAsset = assets[i];
                userState[i].stakedByUser = IERC20(assets[i]).balanceOf(user);
                userState[i].totalStaked = IERC20(assets[i]).totalSupply();
            }
            unclaimedRewards = unclaimedRewards.add(_getUnclaimedRewards(user, userState));

            return unclaimedRewards;

        }

    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
        ) external override returns (uint256) {
            if (amount == 0) {
                return 0;
            }

            address user = msg.sender;
            uint256 unclaimedRewards = _usersUnclaimedRewards[user];

            DistributionTypes.UserStakeInput[] memory userState =
                new DistributionTypes.UserStakeInput[](assets.length);

            for (uint256 i = 0; i < assets.length; i++) {
                userState[i].underlyingAsset = assets[i];
                userState[i].stakedByUser = IERC20(assets[i]).balanceOf(user);
                userState[i].totalStaked = IERC20(assets[i]).totalSupply();
            }

            uint256 accruedRewards = _claimRewards(user, userState);

            if(accruedRewards != 0) {
                unclaimedRewards = unclaimedRewards.add(accruedRewards);
                emit RewardsAccrued(user, accruedRewards);
            }

            if (unclaimedRewards == 0) {
                return 0;
            }

            uint256 amountToClaim = amount > unclaimedRewards ? unclaimedRewards : amount;
            _usersUnclaimedRewards[user] = unclaimedRewards - amountToClaim;

            REWARD_TOKEN.transferFrom(REWARDS_VAULT, to, amountToClaim);

            emit RewardsClaimed(msg.sender, to, amountToClaim);

            return amountToClaim;
        }

    function getUserUnclaimedRewards(address _user) external view returns (uint256) {
        return _usersUnclaimedRewards[_user];
    }

    function getRevision() internal pure override returns (uint256) {
        return HIPO_INCENTIVES_CONTROLLER_REVISION;
    }
}
