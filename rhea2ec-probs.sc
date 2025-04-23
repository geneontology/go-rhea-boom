//> using scala "2.13"
import scala.io.Source

val input = args(0)
var pairs: Set[(String, String)] = Set.empty
var pairsByRhea: Map[String, Set[(String, String)]] = Map.empty
var pairsByEC: Map[String, Set[(String, String)]] = Map.empty
for {
  line <- Source.fromFile(input, "UTF-8").getLines()
  cells = line.split("\t", -1)
  rhea = cells(0)
  ec = cells(3)
} {
  pairs += rhea -> ec
  pairsByRhea = pairsByRhea.updatedWith(rhea) {
    case Some(pairs) => Some(pairs + (rhea -> ec))
    case None        => Some(Set(rhea -> ec))
  }
  pairsByEC = pairsByEC.updatedWith(ec) {
    case Some(pairs) => Some(pairs + (rhea -> ec))
    case None        => Some(Set(rhea -> ec))
  }
}
for ((rhea, ec) <- pairs) {
  val rheaCount = pairsByRhea(rhea).size
  val ecCount = pairsByEC(ec).size
  if ((rheaCount > 1) && (ecCount > 1)) {
    println(s"RHEA:$rhea\tEC:$ec\t0.30\t0.30\t0.30\t0.10")
  } else if (rheaCount > 1) {
    // 0.50	0.19	0.30	0.01
    println(s"RHEA:$rhea\tEC:$ec\t0.09\t0.60\t0.30\t0.01")
  } else if (ecCount > 1) {
    println(s"RHEA:$rhea\tEC:$ec\t0.60\t0.09\t0.30\t0.01")
  } else {
    println(s"RHEA:$rhea\tEC:$ec\t0.19\t0.19\t0.60\t0.02")
  }
}
