using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Response model for claim message operation.
    /// </summary>
    [Serializable]
    public class ClaimMessageResponse
    {
        public ClaimReward[] rewards;
    }
}
