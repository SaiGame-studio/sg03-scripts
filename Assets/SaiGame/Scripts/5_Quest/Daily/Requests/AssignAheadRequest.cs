using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Request body for POST /api/v1/games/{gameId}/daily-quests/{dqPoolId}/assign-ahead
    /// </summary>
    [Serializable]
    public class AssignAheadRequest
    {
        public int days_ahead;
    }
}
