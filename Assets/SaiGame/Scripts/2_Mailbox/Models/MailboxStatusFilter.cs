using System;

namespace SaiGame.Services
{
    /// <summary>
    /// Filter options for local mailbox message filtering.
    /// </summary>
    public enum MailboxStatusFilter
    {
        All,
        Unread,
        Read,
        Claimed,
        Unclaimed
    }
}
