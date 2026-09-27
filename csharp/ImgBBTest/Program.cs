using System.Collections;

namespace Iminetsoft.Dev.ImgBBTest
{
    public static class Program
    {
        public static async Task Main(string[] Args)
        {
            var args = Iminetcore.ConsoleParser.ArgParser.ParseDynamic(Args);

            Console.WriteLine("IMGBB Test Application");

            Environment.GetEnvironmentVariables().Cast<DictionaryEntry>().OrderBy(x => x.Key).ToList().ForEach(x => Console.WriteLine($"\t{x.Key} :: {x.Value}"));

            return;

            var imgbb_token = Environment.GetEnvironmentVariable("IMGBB_TOKEN") ?? args.token ?? args.t;
            var imgbb = new ImgBBApi(imgbb_token);
            var uploaded = new List<string>();

            var files = ((string)args.files ?? (string)args.f).Split(",").ToList();

            if (files.Count()>0)
            {
                uploaded = await imgbb.UploadImgbbAsync(files);
                uploaded.ForEach(f => Console.WriteLine(f));
            }
            else Console.WriteLine("No files added for uploading");
        }
    }
}