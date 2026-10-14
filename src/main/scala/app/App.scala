package app

import app.Core
import app.Interop
import org.rogach.scallop.ScallopConf
import org.rogach.scallop.exceptions.ScallopException
import org.rogach.scallop.flagConverter
import org.rogach.scallop.intConverter
import org.rogach.scallop.stringConverter
import typings.node.childProcessMod.ChildProcess
import typings.node.childProcessMod.ExecException
import typings.node.childProcessMod.exec
import typings.node.fsMod
import typings.node.fsMod.BigIntStats
import typings.node.fsMod.ReadStreamOptions
import typings.node.fsMod.StatSyncOptions
import typings.node.fsMod.Stats
import typings.node.fsMod.createReadStream
import typings.node.fsMod.createWriteStream
import typings.node.fsMod.statSync
import typings.node.fsPromisesMod
import typings.node.nodeStrings.fs
import typings.node.pathMod.^ as path
import typings.node.processMod.global.process
import typings.node.streamPromisesMod.pipeline
import typings.node.utilMod.promisify

import scala.concurrent.Future
import scala.scalajs.js
import scala.scalajs.js.UndefOr
import scala.scalajs.js.timers.setTimeout
import scala.util.Failure
import scala.util.Success
import scala.util.Try

implicit val ec: scala.concurrent.ExecutionContext = scala.concurrent.ExecutionContext.global

val CHUNK_SIZE_DEFAULT = 50331648
val DD_BLOCK_SIZE_DEFAULT = 4194304

class Conf(arguments: Seq[String]) extends ScallopConf(arguments) {

  banner("""Usage: adbflashimg [OPTIONS] <src-img.img> <block-device>
           |Example: adbflashimg system.img /dev/block/system"
           |adbflashimg is a CLI utility for flashing .img files over adb.
           |Options:
           |""".stripMargin)
  val chunkSize = opt[Int](
    name = "chunk-size",
    default = Some(CHUNK_SIZE_DEFAULT),
    noshort = true,
    required = false,
    descr = s"Max size of chunk travelling over USB (bytes). Default: ${CHUNK_SIZE_DEFAULT} (48MiB).",
    validate = (_ > 0)
  )

  val ddBlockSize = opt[Int](
    name = "dd-block-size",
    default = Some(DD_BLOCK_SIZE_DEFAULT),
    noshort = true,
    required = false,
    descr = s"dd chunk size for writing to device storage. Default: ${DD_BLOCK_SIZE_DEFAULT} (4MiB).",
    validate = (_ > 0)
  )
  val srcFile = trailArg[String](
    name = "src-img",
    required = true,
    descr = "Source .img file to be flashed.",
    validate = (_.length > 0)
  )
  val blockDevice = trailArg[String](
    name = "block-device",
    descr = "Block device for .img to be flashed to (located at /dev/block/)."
  )
  val skipCount = opt[Int](
    name = "skip",
    default = Some(0),
    noshort = true,
    required = false,
    descr = "How many chunks to skip. Useful in case of partial failures. Default: 0.",
    validate = (_ >= 0)
  )
  val adbDevice = opt[String](
    name = "adb-device",
    default = None,
    noshort = true,
    required = false,
    descr = "Identifier of adb device (required if you have >1 adb devices).",
    validate = (_.length > 0)
  )

  val debug = opt[Boolean](
    name = "debug",
    noshort = true,
    descr = "Enables debugging mode if specified. Prints out more logs."
  )
  verify()
}

object App {

  def main(x: Array[String]): Unit = {
    val dropCountNode = process.env.get("ADBFLASHIMG_DROP_COUNT")
    val dropCount = dropCountNode.flatMap(undefOr => undefOr.toOption).getOrElse("2")
    val args = Interop.toScalaArray(process.argv.drop(dropCount.toInt))
    val cliConf = new Conf(args)
    try {
      val srcFile = cliConf.srcFile()
      val blockDevice = cliConf.blockDevice()
      val chunkSize = cliConf.chunkSize()
      val skipCount = cliConf.skipCount()
      val ddBlockSize = cliConf.ddBlockSize()
      val debug = cliConf.debug()
      val adbDevice = cliConf.adbDevice.toOption
      if (chunkSize % ddBlockSize != 0) {
        throw new UserFacingException(
          s"dd block size must be whole number divisible of chunk size. Current values: ${chunkSize}, ${ddBlockSize}"
        )
      }
      val ddDividor = chunkSize / ddBlockSize

      var fileSize = 0
      val statOpts = StatSyncOptions()
      statOpts.throwIfNoEntry = false
      val stat = statSync(srcFile, statOpts)
      stat match
        case s: Stats =>
          fileSize = s.size.toInt
        case _ => {
          throw new UserFacingException(s"Input file not found: ${srcFile}")
        }
      if (fileSize == 0) {
        throw new UserFacingException("Input file is empty! Exiting.")
      }

      val fullSrcFile = path.resolve(srcFile)
      val core = Core(chunkSize, ddDividor, fullSrcFile, blockDevice, fileSize, skipCount, debug)
      val f1 = Adb.init(adbDevice)
      f1.onComplete {
        case Failure(exception) => 
          logException(exception, debug)
        case Success(value) =>
          core.sendingLoop()
          core.flashingLoop()
      }
      return ()
    } catch {
      case e: Exception => {
        logException(e, cliConf.debug())
        return ()
      }
    }
  }

  def logException(exception: Throwable, debug: Boolean): Unit = {
    if (debug) {
      exception.printStackTrace()
    } else {
      val msg = unwind(exception)
      if (msg != null) {
        println(unwind(exception))
      }
    }
  }

  def unwind(exception: Throwable): String = {
    val messages = collection.mutable.ListBuffer[String]()
    var current = exception

    while (current != null) {
      val msg = current.getMessage
      if (msg != null) {
        messages += msg
      }
      current = current.getCause
    }

    messages.mkString(". ")
  }
}
