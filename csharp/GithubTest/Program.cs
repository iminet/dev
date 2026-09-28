using MimeKit;
using Octokit;

namespace Iminetsoft.Dev.GithubTest
{
    public static class Program
    {
        public static async Task Main(string[] Args)
        {
            var args = Iminetsoft.Iminetcore.ConsoleParser.ArgParser.Parse(Args);

            var github = new GitHubClient(new ProductHeaderValue("GithubTest"));
            github.Credentials = new Credentials(Environment.GetEnvironmentVariable("GITHUB_TOKEN"));

            Console.WriteLine("GITHUB TEST APPLICATION");

            foreach(var arg in args.ToList())
            {
                switch(arg.Key)
                {
                    case "r":
                    case "repositories":
                        var repos = await github.Repository.GetAllForCurrent();
                        repos.ToList().ForEach(r => Console.WriteLine($"{r.Name}"));
                    break;

                    case "i":
                    case "issues":
                        var issues = await github.Issue.GetAllForCurrent(new IssueRequest()
                        {
                            State = ItemStateFilter.Open,
                            SortProperty = IssueSort.Created,
                            SortDirection = SortDirection.Descending    
                        });
                        issues.ToList().ForEach(i => Console.WriteLine($"{i.Repository.Name}/{i.Title}"));
                    break;

                    case "u":
                    case "user":
                        var userinfo = await github.User.Current();
                        (new Dictionary<string,object>()
                        {
                            { "Name", userinfo.Name },
                            { "Username", userinfo.Login },
                            { "Disk Usage", $"{userinfo.DiskUsage ?? 0} kB ({userinfo.DiskUsage/1024 ?? 0} MB)" },
                            { "Followers", userinfo.Followers },
                            { "Following", userinfo.Following },
                            { "Avatar URL", userinfo.AvatarUrl },
                            { "Profile URL", userinfo.HtmlUrl },
                        }).ToList().ForEach(x => Console.WriteLine($"{x.Key}: {x.Value}"));
                    break;
                }
            }
        }
    }
}