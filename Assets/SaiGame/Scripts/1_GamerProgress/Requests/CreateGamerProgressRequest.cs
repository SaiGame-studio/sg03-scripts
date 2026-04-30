using System;

namespace SaiGame.Services
{
    [Serializable]
    public class CreateGamerProgressRequest
    {
        public string user_id;
        public string game_id;
        public int experience = 0;
        public int gold = 0;
        public string game_data = "{}";
    }
}
