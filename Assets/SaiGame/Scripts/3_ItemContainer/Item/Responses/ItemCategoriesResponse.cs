using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Response from GET /api/v1/items/categories
    /// </summary>
    [Serializable]
    public class ItemCategoriesResponse
    {
        public string[] categories;
    }
}
