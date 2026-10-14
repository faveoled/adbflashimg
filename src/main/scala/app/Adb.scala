package app

import typings.adbTs.libUtilTypesMod.IDevice
import typings.adbTs.mod.Client
import typings.node.fsMod.ReadStream

import scala.concurrent.Future
import scala.scalajs.js
import scala.util.Failure
import scala.util.Success
import scala.util.Try

object Adb {

  var device: IDevice = null
  var client: Client = null

  def init(adbDevice: Option[String]): Future[Unit] = {
    val adbClient = Client()
    client = adbClient
    val fut = adbClient.listDevices().toFuture
    fut.flatMap(v => {
      val filtered = v.filter(i => {
        if (adbDevice.isDefined) {
          adbDevice.get == i.id
        } else {
          true
        }
      })
      if (filtered.length == 0) {
        val context = adbDevice
          .map(d => s" with ID=${d}") 
          .getOrElse("")
        val all = "[" + v.map(d => d.id).mkString(", ") + "]"
        val errMsg = s"No adb device${context} found. IDs available: ${all}"
        Future.failed(UserFacingException(errMsg))
      } else {
        device = filtered(0)
        Future.successful(())
      }
    })
  }

  def push(rs: ReadStream, path: String): Future[Unit] = {
    client.pushDataToFile(device.id, rs.asInstanceOf[typings.node.streamMod.Readable], path)
          .toFuture
  }
}
