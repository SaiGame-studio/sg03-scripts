using System;

namespace SaiGame.Services
{
    [Serializable]
    public class UpdateGamerProgressRequest
    {
        public int experience_delta;
        public int gold_delta;
        public string game_data;
    }
}
