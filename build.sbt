ThisBuild / scalaVersion := "3.3.8"

lazy val hello = (project in file("."))
  .enablePlugins(ScalaJSPlugin, ScalablyTypedConverterPlugin)
  .settings(
    name := "Scala.js Tutorial",
    scalaJSUseMainModuleInitializer := true,
    libraryDependencies += "org.rogach" %%% "scallop" % "6.0.0",
    libraryDependencies += "com.lihaoyi" %%% "utest" % "0.9.5" % "test",
    testFrameworks += new TestFramework("utest.runner.Framework"),
    Compile / npmDependencies ++= Seq(
      "@types/node" -> "24.2.1",
      "adb-ts" -> "6.2.0"
    ),
    stOutputPackage := "typings"
  )

