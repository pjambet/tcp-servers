import java.net.{ServerSocket, Socket}
import java.io.{BufferedReader, InputStreamReader, PrintWriter}
import java.util.concurrent.{ConcurrentHashMap, Executors}
import scala.collection.mutable
import scala.concurrent.{Await, ExecutionContext, Future}
import scala.concurrent.duration.Duration

object Main {

  private def accept(
      server: ServerSocket
  )(implicit ec: ExecutionContext): Future[Socket] = {
    Future { server.accept() }
  }

  private def handleClient(
      client: Socket,
      db: ConcurrentHashMap[String, String],
      executionContext: ExecutionContext
  ): Future[Unit] = {
    Future {
      while (true) {
        val input = new BufferedReader(new InputStreamReader(client.getInputStream)).readLine()
        if (input == null) {
          client.close()
          return Future.successful(())
        }

        val output = new PrintWriter(client.getOutputStream, true)
        output.println(s"Hello: $input 👋")
      }
    }(executionContext)
  }

  private def continuouslyAccept(
      server: ServerSocket,
      clients: collection.mutable.Set[Socket],
      db: ConcurrentHashMap[String, String],
      executionContext: ExecutionContext
  )(implicit ec: ExecutionContext): Future[Unit] = {
    accept(server).flatMap { client =>
      println(s"accepted $client")
      clients.add(client)
      val _ = handleClient(client, db, executionContext)
      continuouslyAccept(server, clients, db, executionContext)
    }
  }

  def main(args: Array[String]): Unit = {
    import ExecutionContext.Implicits.global
//collection.immutable.M
    val db = new ConcurrentHashMap[String, String]()
    val executor = Executors.newVirtualThreadPerTaskExecutor()
    val ec = ExecutionContext.fromExecutor(executor)
    val clients = collection.mutable.Set[Socket]()
    val server = new ServerSocket(3000)
    Await.result(continuouslyAccept(server, clients, db, ec), Duration.Inf)
  }
}
