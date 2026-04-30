using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Wrapper used to parse the start-quest response body.
    /// Maps directly to the flat response (no wrapper object).
    /// </summary>
    [Serializable]
    public class StartQuestResponse
    {
        public string id;
        public string studio_id;
        public string game_id;
        public string user_id;
        public string quest_definition_id;
        public string status;
        public int version;
        public string created_at;
        public string updated_at;
    }
}
