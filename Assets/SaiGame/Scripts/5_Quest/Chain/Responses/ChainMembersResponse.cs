using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Response from GET /api/v1/games/{gameId}/quests/chains/{chainId}/members
    /// </summary>
    [Serializable]
    public class ChainMembersResponse
    {
        public ChainMemberData[] members;
    }
}
