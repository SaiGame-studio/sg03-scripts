using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Server response for POST /api/v1/games/{gameId}/quests/{questDefinitionId}/claim
    /// </summary>
    [Serializable]
    public class ClaimQuestResponse
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string quest_definition_id;
        public string progress_id;
        public string idempotency_key;
        public ClaimQuestGrantedReward[] rewards_granted;
        public string claimed_at;
    }
}
