import scala.concurrent.{Await, ExecutionContext, Future}
import scala.concurrent.duration.DurationInt

object Main {
  def main(args: Array[String]): Unit = {
    import ExecutionContext.Implicits.global

    val f = Future {
      "Hello world!"
    }

    Await.result(f.map { println(_) }, 1.second)
  }
}
