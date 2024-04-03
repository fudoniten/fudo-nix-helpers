(ns build
  (:require [clojure.tools.build.api :as b]
            [clojure.pprint :refer [pprint]]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.set :refer [difference]])
  (:import java.io.File))

(def required-keys
  #{:verbose
    :lib
    :version
    :basis
    :class-dir
    :namespace
    :name
    :target})

(defn- pthru [o] (pprint o) o)

(defn lib-name [ns name]
  (symbol (str ns "/" name)))

(defn add-lib-name [{:keys [namespace name] :as params}]
  (assoc params :lib (lib-name namespace name)))

(defn basis [params]
  (assoc params :basis
         (b/create-basis {:project "deps.edn"})))

(defn- add-class-dir [{:keys [target] :as params}]
  (assoc params :class-dir
         (format "%s/classes" target)))

(defn- jar-file [{:keys [target version name]}]
  (format "%s/%s-%s.jar" target name version))

(defn- uberjar-file [{:keys [target version name]}]
  (format "%s/%s-uber-%s.jar" target name version))

(def default-params
  {
   :verbose   false
   :version   "DEV"
   :namespace "fudo.org"
   :src-dirs  []
   })

(defn clean [{:keys [target] :as params}]
  (b/delete {:path (str target)})
  params)

(defn compile-java [{:keys [verbose java-src class-dir basis] :as params}]
  (if java-src
    (let [java-src (str/split (str java-src) #",")]
      (when verbose (println (format "compiling java files in %s..." java-src)))
      (b/javac {:src-dirs   java-src
                :class-dir  class-dir
                :basis      basis
                :javac-opts ["-source" "16" "-target" "16"]})
      (update params :src-dirs conj java-src))
    (do (when verbose (println (format "skipping java compile, no java-src specified...")))
        params)))

(defn compile-clj [{:keys [verbose clj-src class-dir basis] :as params}]
  (if clj-src
    (let [clj-src (str/split (str clj-src) #",")]
      (when verbose (println (format "compiling clj files in %s..." clj-src)))
      (b/compile-clj {:basis     basis
                      :src-dirs  clj-src
                      :class-dir class-dir})
      (update params :src-dirs conj clj-src))
    (do (when verbose (println (format "skipping clj compile, no clj-src specified...")))
        params)))

(defn- read-metadata-from-file [filename]
  (if (.exists (io/file filename))
    (do (println (format "reading metadata from %s..." filename))
        (-> filename
            (slurp)
            (edn/read-string)))
    (println (format "skipping nonexistent metadata file %s..." filename))))

(defn default [d] (fn [x] (if x x d)))

(defn ensure-keys [m ks]
  (let [missing-keys (->> m (keys) (set) (difference ks))]
    (when (not (empty? missing-keys))
      (throw (RuntimeException. (format "Missing required keys: %s"
                                        (str/join ", " (map name missing-keys)))))))
  m)

(defn- add-basis [params]
  (assoc params :basis (b/create-basis {:project "deps.edn"})))

(defn- process-params [base-params]
  (-> default-params
      (merge base-params)
      (merge (read-metadata-from-file
              (or (:metadata base-params)
                  "metadata.edn")))
      (add-basis)
      (add-lib-name)
      (add-class-dir)
      (ensure-keys required-keys)
      (update :target str)
      (update :version str)
      (update :name str)
      (update :namespace str)))

(defn write-pom [{:keys [lib version basis src-dirs verbose class-dir] :as params}]
  (when verbose (println (format "writing POM file to %s..." class-dir)))
  (b/write-pom {:class-dir class-dir
                :lib       lib
                :version   version
                :basis     basis
                :src-dirs  src-dirs})
  params)

(defn- copy-src-to-target [{:keys [verbose src-dirs class-dir] :as params}]
  (when verbose (println (format "copying source files from %s to %s..."
                                 src-dirs class-dir)))
  (b/copy-dir {:src-dirs src-dirs :target-dir class-dir})
  params)

(defn- print-params [params]
  (when (:verbose params)
    (println "parameters: ")
    (pprint params)
    (println))
  params)

(defn- finalize [params]
  (println "done!")
  params)

(defn- write-jar [{:keys [class-dir verbose] :as params}]
  (let [jarfile (jar-file params)]
    (when verbose (println (format "writing jar file to %s..." jarfile)))
    (b/jar {:class-dir class-dir :jar-file jarfile})
    params))

(defn- write-uberjar [{:keys [verbose class-dir basis] :as params}]
  (let [uberjar (uberjar-file params)]
    (when verbose (println (format "writing uberjar file to %s..." uberjar)))
    (b/uber {:class-dir class-dir :uber-file uberjar :basis basis})
    params))

(defn- install [{:keys [verbose basis lib version jar class-dir] :as params}]
  (when verbose (println (format "installing %s..." jar)))
  (b/install {:basis     basis
              :lib       lib
              :version   version
              :jar-file  jar
              :class-dir class-dir})
  params)

(defn jar [params]
  (-> params
      (process-params)
      (add-basis)
      (compile-java)
      (compile-clj)
      (write-pom)
      (copy-src-to-target)
      (write-jar)
      (finalize)))

(defn uberjar [params]
  (-> params
      (process-params)
      (add-basis)
      (compile-java)
      (compile-clj)
      (write-pom)
      (copy-src-to-target)
      (write-uberjar)
      (finalize)))

(defn install [params]
  (-> params
      (process-params)
      (write-jar)
      (install)))
