using System.Net;

using var listener = new HttpListener();
listener.Prefixes.Add("http://localhost:8001/");

listener.Start();

Console.WriteLine("Listening on port 8001...");

while (true)
{
    HttpListenerContext ctx = listener.GetContext();
    using HttpListenerResponse resp = ctx.Response;

    resp.StatusCode = (int) HttpStatusCode.OK;
    resp.StatusDescription = "Status OK";
}
