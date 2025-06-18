// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./library/SafeERC20.sol";
import "./library/SafeMath.sol";
import "./VeBeat.sol";

contract VeBeatVote is  OwnableUpgradeable, PausableUpgradeable  {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public rank_1_rewards;
    uint256 public rank_2_rewards;
    uint256 public rank_3_rewards;
    uint256 public rank_1_buf;
    uint256 public rank_2_buf;
    uint256 public rank_3_buf;
    uint256 public each_voter_increases_rewards;
    uint256 public max_num_of_rewards;

    uint32 public votingDuration;
    uint32 public votingCountdown;

    struct UserVotingRecords {
        uint256 songIndex;
        uint256 numOfVotes;
        uint256 claimedRewards;
        address user;
    }

    struct RoundVotingRecords {
        bool closed;
        uint32 roundNum;
        uint32 startTime;
        uint32 endTime;
        uint32 claimTime;
        uint32 numOfVoters;
        uint32 rank_1_index;
        uint32 rank_2_index;
        uint32 rank_3_index;
        uint256 totalNumOfVotes;
        uint256[10] songIds;
        uint256[10] numOfVotesPerSong;
        address[10] songOwners;
    }

    UserVotingRecords[] public userVotingRecords;
    RoundVotingRecords[] public roundVotingRecords;
    mapping(uint32=>mapping(address=>uint32)) public roundToUserVotingIndex;

    address public beat;
    VeBeat public veBeat;
    mapping(address => bool) public authControllers;

    event SetVotingSongs(uint256[10] _songIds, address[10] _users, uint32 _startTime, uint32 _round);
    event Vote(address indexed _voter, uint32 indexed _index, uint256 _numOfVotes);
    event Claim(address indexed _voter, uint32 indexed _roundNum, uint256 _numOfVotes, uint256 _rewards);
    event CountingVotes(address indexed _sender, uint32 indexed _roundNum, uint32 _rank_1_index, uint32 _rank_2_index, uint32 _rank_3_index);
    event RankRewards(address _rank_1_owner, uint256 _rank_1_rewards, address _rank_2_owner, uint256 _rank_2_rewards, address _rank_3_owner, uint256 _rank_3_rewards);

    function initialize(
        address _beat,
        address _veBeat
    ) public initializer {
        __Ownable_init();

        require(_beat != address(0), "VeBeatVote: unexpected zero address for _beat");
        require(_veBeat != address(0), "VeBeatVote: unexpected zero address for _veBeat");
        beat = _beat;
        veBeat = VeBeat(_veBeat);
        votingDuration = 7 days - 1 hours;
        votingCountdown = 1 hours;
        rank_1_rewards = 1000 * 1e18;
        rank_2_rewards = 500 * 1e18;
        rank_3_rewards = 200 * 1e18;
        rank_1_buf = 50;
        rank_2_buf = 25;
        rank_3_buf = 10;
        each_voter_increases_rewards = 50 * 1e18;
        max_num_of_rewards = 50000 * 1e18;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function balanceOf(address _token) public view returns(uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    function setAuthControllers(address _controller, bool _enable) external onlyOwner {
        authControllers[_controller] = _enable;
    }

    function setVotingTime(uint32 _duration, uint32 _countdown) external onlyOwner {
        votingDuration = _duration;
        votingCountdown = _countdown;
    }

    function setRankRewards(uint256 _rank_1_rewards, uint256 _rank_2_rewards, uint256 _rank_3_rewards) external onlyOwner {
        require(_rank_1_rewards < 1e18 && _rank_2_rewards < 1e18 && _rank_3_rewards < 1e18);
        rank_1_rewards = _rank_1_rewards * 1e18;
        rank_2_rewards = _rank_2_rewards * 1e18;
        rank_3_rewards = _rank_3_rewards * 1e18;
    }

    function setRankBuf(uint256 _rank_1_buf, uint256 _rank_2_buf, uint256 _rank_3_buf) external onlyOwner {
        rank_1_buf = _rank_1_buf;
        rank_2_buf = _rank_2_buf;
        rank_3_buf = _rank_3_buf;
    }

    function setEachVoterIncreasesRewards(uint256 _rewards) external onlyOwner {
        require(_rewards < 1e18);
        each_voter_increases_rewards = _rewards * 1e18;
    }

    function setMaxRewards(uint256 _rewards) external onlyOwner() {
        require(_rewards < 1e18);
        max_num_of_rewards = _rewards * 1e18;
    }

    function setVotingSongs(uint256[10] memory _songIds, address[10] memory _owners, uint32 _startTime) external {
        require(authControllers[_msgSender()], "No auth");
        uint32 curTime = uint32(block.timestamp);
        require(_startTime >= curTime, "_startTime < curTime");
        uint32 roundNum = uint32(roundVotingRecords.length);
        if (roundNum> 0) {
            RoundVotingRecords memory curRound = roundVotingRecords[roundNum - 1];
            require(_startTime >= curRound.claimTime && curRound.closed == true, "Not closed");
        }

        RoundVotingRecords memory round;
        round.startTime = _startTime;
        round.endTime = _startTime + votingDuration;
        round.claimTime = round.endTime + votingCountdown;
        round.roundNum = roundNum + 1;
        for (uint256 i = 0; i < 10; ++i) {
            round.songIds[i] = _songIds[i];
            round.songOwners[i] = _owners[i];
        }
        roundVotingRecords.push(round);
        emit SetVotingSongs(_songIds, _owners, _startTime, round.roundNum);
    }

    function vote(uint32 _index, uint256 _numOfVotes) external whenNotPaused {
        address sender = _msgSender();
        require(_index > 0 && _index <= 10, "Invalid index");
        require(_numOfVotes >= 1e18, "Invalid numOfVotes");
        uint256 userVeBeatBalance = veBeat.balanceOf(sender);
        require(userVeBeatBalance >= _numOfVotes, "Not enough veBeat");
        veBeat.burnFrom(sender, _numOfVotes);
        uint32 roundNum = uint32(roundVotingRecords.length);
        require(roundNum > 0, "Invalid round");
        RoundVotingRecords memory round = roundVotingRecords[roundNum - 1];
        uint32 curTime = uint32(block.timestamp);
        require(curTime >= round.startTime && curTime < round.endTime && round.closed == false, "Invalid vote time");

        uint32 recordsIndex = roundToUserVotingIndex[roundNum][sender];
        if (recordsIndex == 0) {
            round.numOfVoters += 1;
            UserVotingRecords memory votingUser;
            votingUser.songIndex = _index;
            votingUser.numOfVotes = _numOfVotes;
            votingUser.user = sender;
            userVotingRecords.push(votingUser);
            roundToUserVotingIndex[roundNum][sender] = uint32(userVotingRecords.length);
        } else {
            UserVotingRecords memory votingUser = userVotingRecords[recordsIndex - 1];
            require(votingUser.songIndex == _index, "Invalid index");
            votingUser.numOfVotes += _numOfVotes;
            userVotingRecords[recordsIndex - 1] = votingUser;
        }

        round.totalNumOfVotes += _numOfVotes;
        round.numOfVotesPerSong[_index-1] += _numOfVotes;
        roundVotingRecords[roundNum - 1] = round;
        emit Vote(sender, _index, _numOfVotes);
    }

    function claim(uint32 _roundNum) external whenNotPaused {
        address sender = _msgSender();
        require(_roundNum > 0 && _roundNum <= uint32(roundVotingRecords.length), "Invalid round num");
        RoundVotingRecords memory round = roundVotingRecords[_roundNum - 1];
        uint32 curTime = uint32(block.timestamp);
        require(curTime >= round.claimTime && round.closed == true, "Voting is not yet closed");

        uint32 recordsIndex = roundToUserVotingIndex[_roundNum][sender];
        require(recordsIndex > 0, "Invalid voter");
        UserVotingRecords memory votingUser = userVotingRecords[recordsIndex - 1];
        require(votingUser.claimedRewards == 0, "Already claimed rewards");
        uint256 totalRewards = round.numOfVoters * each_voter_increases_rewards;
        if (totalRewards > max_num_of_rewards) {
            totalRewards = max_num_of_rewards;
        }

        uint256 rewardsAmount = votingUser.numOfVotes * totalRewards / round.totalNumOfVotes;
        uint256 buf = 0;
        if (votingUser.songIndex == round.rank_1_index) {
            buf = rank_1_buf;
        } else if (votingUser.songIndex == round.rank_2_index) {
            buf = rank_2_buf;
        } else if (votingUser.songIndex == round.rank_3_index) {
            buf = rank_3_buf;
        }
        if (buf > 0) {
            rewardsAmount += rewardsAmount * buf / 100;
        }
        require(rewardsAmount > 0, "Rewards == 0");
        IERC20(beat).safeTransfer(sender, rewardsAmount);
        votingUser.claimedRewards = rewardsAmount;

        userVotingRecords[recordsIndex - 1] = votingUser;
        emit Claim(sender, _roundNum, votingUser.numOfVotes, votingUser.claimedRewards);
    }

    function countingVotes() external {
        require(authControllers[_msgSender()], "No auth");
        uint32 roundNum = uint32(roundVotingRecords.length);
        require(roundNum > 0, "No record");
        RoundVotingRecords memory round = roundVotingRecords[roundNum - 1];
        uint32 curTime = uint32(block.timestamp);
        require(curTime >= round.endTime, "Voting is not yet closed");
        require(round.closed == false, "Counting votes closed");

        uint32 rank_1_index = 0;
        uint32 rank_2_index = 0;
        uint32 rank_3_index = 0;
        uint256 rank_1_votes = 0;
        uint256 rank_2_votes = 0;
        uint256 rank_3_votes = 0;
        while (true) {
            uint32 i = 0;
            while (i <= 8) {
                bool change = false;
                for (uint32 j = i + 1; j <= 9; ++j) {
                    if (round.numOfVotesPerSong[i] >= round.numOfVotesPerSong[j]) {
                        continue;
                    }
                    i = j;
                    change = true;
                    break;
                }

                if (change == false) {
                    break;
                } 
            }
            if (rank_1_index == 0) {
                rank_1_index = i + 1;
                rank_1_votes = round.numOfVotesPerSong[i];
            } else if (rank_2_index == 0) {
                rank_2_index = i + 1;
                rank_2_votes = round.numOfVotesPerSong[i];
            } else if (rank_3_index == 0) {
                rank_3_index = i + 1;
                rank_3_votes = round.numOfVotesPerSong[i];
                break;
            }
            round.numOfVotesPerSong[i] = 0;
        }

        if (rank_1_votes > 0) {
            roundVotingRecords[roundNum - 1].rank_1_index = rank_1_index;
        } else {
            rank_1_index = 0;
        }

        if (rank_2_votes > 0) {
            roundVotingRecords[roundNum - 1].rank_2_index = rank_2_index;
        } else {
            rank_2_index = 0;
        }

        if (rank_3_votes > 0) {
            roundVotingRecords[roundNum - 1].rank_3_index = rank_3_index;
        } else {
            rank_3_index = 0;
        }

        roundVotingRecords[roundNum - 1].closed = true;
        emit CountingVotes(_msgSender(), roundNum, rank_1_index, rank_2_index, rank_3_index);

        address _rank_1_owner = address(0);
        address _rank_2_owner = address(0);
        address _rank_3_owner = address(0);
        uint256 _rank_1_rewards = 0;
        uint256 _rank_2_rewards = 0;
        uint256 _rank_3_rewards = 0;
        if (rank_1_index > 0) {
            _rank_1_owner = round.songOwners[rank_1_index - 1];
            _rank_1_rewards = rank_1_rewards;
            if (_rank_1_owner != address(0)) {
                IERC20(beat).safeTransfer(_rank_1_owner, _rank_1_rewards);
            }
        }
        if (rank_2_index > 0) {
            _rank_2_owner = round.songOwners[rank_2_index - 1];
            _rank_2_rewards = rank_2_rewards;
            if (_rank_2_owner != address(0)) {
                IERC20(beat).safeTransfer(_rank_2_owner, _rank_2_rewards);
            }
        }
        if (rank_3_index  > 0) {
            _rank_3_owner = round.songOwners[rank_3_index - 1];
            _rank_3_rewards = rank_3_rewards;
            if (_rank_3_owner != address(0)) {
                IERC20(beat).safeTransfer(_rank_3_owner, _rank_3_rewards);
            }
        }
        emit RankRewards(_rank_1_owner, _rank_1_rewards, _rank_2_owner, _rank_2_rewards, _rank_3_owner, _rank_3_rewards);
    }

    function voterInfo(address _user, uint32 _roundNum) public view returns(
        uint256 voteIndex,
        uint256 numOfVotes,
        uint256 pendingRewards, 
        uint256 claimedRewards
    ) {
        voteIndex = 0;
        numOfVotes = 0;
        pendingRewards = 0;
        claimedRewards = 0;
        if (_roundNum == 0 || _roundNum > uint32(roundVotingRecords.length)) {
            return(voteIndex, numOfVotes, pendingRewards, claimedRewards);
        }

        uint32 recordsIndex = roundToUserVotingIndex[_roundNum][_user];
        if (recordsIndex == 0) {
            return(voteIndex, numOfVotes, pendingRewards, claimedRewards);
        }

        UserVotingRecords memory votingUser = userVotingRecords[recordsIndex - 1];
        voteIndex = votingUser.songIndex;
        numOfVotes = votingUser.numOfVotes;

        RoundVotingRecords memory round = roundVotingRecords[_roundNum - 1];
        uint32 curTime = uint32(block.timestamp);
        if (curTime < round.endTime || round.closed == false) {
            return(voteIndex, numOfVotes, pendingRewards, claimedRewards);
        }

        if (votingUser.claimedRewards > 0) {
            claimedRewards = votingUser.claimedRewards;
            return(voteIndex, numOfVotes, pendingRewards, claimedRewards);
        }

        uint256 totalRewards = round.numOfVoters * each_voter_increases_rewards;
        if (totalRewards > max_num_of_rewards) {
            totalRewards = max_num_of_rewards;
        }

        uint256 rewardsAmount = votingUser.numOfVotes * totalRewards / round.totalNumOfVotes;
        uint256 buf = 0;
        if (votingUser.songIndex == round.rank_1_index) {
            buf = rank_1_buf;
        } else if (votingUser.songIndex == round.rank_2_index) {
            buf = rank_2_buf;
        } else if (votingUser.songIndex == round.rank_3_index) {
            buf = rank_3_buf;
        }
        if (buf > 0) {
            rewardsAmount += rewardsAmount * buf / 100;
        }
        pendingRewards = rewardsAmount;
        return(voteIndex, numOfVotes, pendingRewards, claimedRewards);
    }

    function currentRoundVoting() public view returns(RoundVotingRecords memory roundVoting) {
        uint32 roundNum = uint32(roundVotingRecords.length);
        if (roundNum == 0) {
            return roundVoting;
        }

        roundVoting = roundVotingRecords[roundNum - 1];
        return roundVoting;
    }

    function roundVotingRecordsLength() public view returns(uint32) {
        return uint32(roundVotingRecords.length);
    }

    function getRoundVotingRercords(uint32 _index, uint32 _len) public view returns(RoundVotingRecords[] memory details, uint8 len) {
        require(_len <= 100 && _len != 0);
        details = new RoundVotingRecords[](_len);
        len = 0;

        uint256 bal = uint32(roundVotingRecords.length);
        if (bal == 0 || _index >= bal) {
            return (details, len);
        }

        for (uint8 i = 0; i < _len; ++i) {
            details[i] = roundVotingRecords[_index];
            ++_index;
            ++len;
            if (_index >= bal) {
                return (details, len);
            }
        }
        return (details, len);
    }

    function withdraw(address _token, address _to, uint256 _amount) external onlyOwner {
        uint256 tokenBal = IERC20(_token).balanceOf(address(this));
        if (_amount == 0 || _amount >= tokenBal) {
            _amount = tokenBal;
        }
        IERC20(_token).safeTransfer(_to, _amount);
    }
}