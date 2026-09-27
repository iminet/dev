using System.Collections;
using Octokit;

namespace Iminetsoft.Dev.GithubTest
{
    public static class Program
    {
        public static async Task Main(string[] Args)
        {
            var args = Iminetcore.ConsoleParser.ArgParser.ParseDynamic(Args);

            var github = new GitHubClient(new ProductHeaderValue("GithubTest"));
            github.Credentials = new Credentials(Environment.GetEnvironmentVariable("GITHUB_TOKEN"));

            var repos = await github.Repository.GetAllForCurrent();

            repos.ToList().ForEach(r => Console.WriteLine($"{r.Name}"));
        }
    }
}