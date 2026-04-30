using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Paginated response from GET /api/v1/games/{gameId}/quest-claims
    /// </summary>
    [Serializable]
    public class QuestClaimsResponse
    {
        public QuestClaimRecord[] claims;
        public int limit;
        public int offset;
        public int total;
    }
}
