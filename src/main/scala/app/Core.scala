package app

import org.rogach.scallop.ScallopConf
import org.rogach.scallop.flagConverter
import org.rogach.scallop.intConverter
import org.rogach.scallop.stringConverter
import typings.node.childProcessMod.ChildProcess
import typings.node.childProcessMod.ExecException
import typings.node.childProcessMod.SpawnOptions
import typings.node.childProcessMod.exec
import typings.node.childProcessMod.spawn
import typings.node.fsMod.BigIntStats
import typings.node.fsMod.ReadStreamOptions
import typings.node.fsMod.StatSyncOptions
import typings.node.fsMod.Stats
import typings.node.fsMod.createReadStream
import typings.node.fsMod.createWriteStream
import typings.node.fsMod.mkdirSync
import typings.node.fsMod.statSync
import typings.node.fsPromisesMod
import typings.node.nodeStrings
import typings.node.nodeStrings.fs
import typings.node.pathMod.^ as path
import typings.node.processMod.global.process
import typings.node.streamPromisesMod.pipeline
import typings.node.utilMod.promisify

import scala.concurrent.Future
import scala.scalajs.js
import scala.scalajs.js.Promise
import scala.scalajs.js.UndefOr
import scala.scalajs.js.timers.setTimeout
import scala.util.Failure
import scala.util.Success
import typings.node.fsMod.ReadStream

case class ExecResult(stdout: String, stderr: String)

class Core(val chunkSize: Int, val ddDividor: Int, srcFile: String, blockDevice: String, fileSize: Int, skipCount: Int, debug: Boolean) {
  val LOOP_DELAY = 50L
  var chunkCount = js.Math.ceil(fileSize.toDouble / chunkSize).toInt
  var flashedCount = skipCount.toLong
  var sentCount = skipCount.toLong

  def execAsync(cmd: String): Future[ExecResult] = {
    return new js.Promise[ExecResult]((resolve, reject) => { 
      if (debug) {
        println(s"cmd: ${cmd}")
      }
      exec(cmd, (error, stdin, stderr) => {
        if (error != null) {
          reject(error)
        } else {
          resolve(ExecResult(stdin, stderr))
        }
      })
    }).toFuture
  }

  def twrpFileName(chunkNum: Long): String = {
    s"/tmp/adbflashimg.${chunkNum}.bin"
  }

  def sendChunk(srcFile: String, startPos: Long, endPosInclusive: Long, targetFile: String): Future[Unit] = {
    val opts = new js.Object().asInstanceOf[js.Dynamic]
    opts.updateDynamic("start")(startPos)
    opts.updateDynamic("end")(endPosInclusive)
    val rs: ReadStream = createReadStream(srcFile, opts.asInstanceOf[ReadStreamOptions])
    Adb.push(rs, targetFile)
  }

  def sendingLoop(): Unit = {
    if (sentCount == chunkCount) {
      if (debug) {
        println("Sending done")
      }
      return
    }
    if (sentCount - flashedCount >= 5) {
      setTimeout(LOOP_DELAY.toDouble) {
        sendingLoop()
      }
      return
    }
    val currentChunk = sentCount + 1
    val targetFile = twrpFileName(currentChunk)

    val endPos = Math.min((sentCount * chunkSize) + chunkSize, fileSize - 1)
    val writeF = sendChunk(srcFile, sentCount * chunkSize, endPos, targetFile)

    writeF.onComplete(t => {
      t match
        case Success(value) => {
          if (debug) {
            println(s"sent chunk ${currentChunk}/${chunkCount} over usb")
          }
          sentCount = sentCount + 1          
        }
        case Failure(exception) => {
          println(s"chunk ${currentChunk}/${chunkCount} adb push failed: ${exception.getMessage()}")
        }
      setTimeout(LOOP_DELAY.toDouble) {
        sendingLoop()
      }
    })
  }

  def flashingLoop(): Unit = {
    if (flashedCount == chunkCount) {
      println("Flashing done")
      return
    }
    if (flashedCount == sentCount) {
      // waiting for next send iteration
      setTimeout(LOOP_DELAY.toDouble) {
        flashingLoop()
      }
      return
    }
    val currentChunk = flashedCount + 1
    val flashCmd = s"adb shell dd if=${twrpFileName(currentChunk)} of=${blockDevice} bs=${chunkSize / ddDividor} seek=${(currentChunk - 1) * ddDividor}"
    val rmCmd = s"adb shell rm ${twrpFileName(currentChunk)}"
    val f1 = execAsync(flashCmd)
      .flatMap(_ => {
        execAsync(rmCmd)
      })

    f1.onComplete(t => {
      t match
        case Success(value) => {
          println(s"Flashed chunk ${currentChunk}/${chunkCount}")
          flashedCount = currentChunk
        }
        case Failure(exception) => {
          println(s"Chunk ${currentChunk}/${chunkCount} flash failed: ${exception.getMessage}")
        }
      setTimeout(LOOP_DELAY.toDouble) {
        flashingLoop()
      }
    })
  }
}
