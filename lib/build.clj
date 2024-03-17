(ns build
  (:require [clojure.tools.build.api :as b]
            [clojure.pprint :refer [pprint]]
            [clojure.edn :as edn]))

;; (def lib 'org.fudo/notifier)

(defn lib-name [ns name]
  (symbol (str ns "/" name)))

(defn insert-lib-name [{:keys [namespace name] :as params}]
  (assoc params :lib (lib-name namespace name)))

(defn basis [params]
  (assoc params :basis
         (b/create-basis {:project "deps.edn"})))

(defn- class-dir [{:keys [target] :as params}]
  (assoc params :class-dir
         (format "%s/classes" target)))

(defn- jar-file [{:keys [target version]
                  :or   {version default-version}
                  :as   params}]
  (assoc params :jar
         (format "%s/%s-%s.jar" target (name lib) version)))

(defn- uberjar-file [{:keys [target version]
                      :or   {version default-version}
                      :as   params}]
  (assoc params :uberjar
         (format "%s/%s-uber-%s.jar" target (name lib) version)))

(def default-params
  {
   :verbose   false
   :version   "DEV"
   :namespace "fudo.org"
   :src-dirs  []
   })

(defn clean [{:keys [target] :as params}]
  (b/delete {:path target})
  params)

(defn compile-java [{:keys [verbose java-src] :as params}]
  (if java-src
    (do
      (when verbose (println (format "compiling java files in %s..." java-src)))
      (b/javac {:src-dirs   [java-src]
                :class-dir  (class-dir params)
                :basis      basis
                :javac-opts ["-source" "16" "-target" "16"]})
      (update params :src-dirs conj java-src))
    (do (when verbose (println (format "skipping java compile, no java-src specified...")))
        params)))

(defn compile-clj [{:keys [verbose clj-src] :as params}]
  (if clj-src
    (do
      (when verbose (println (format "compiling clj files in %s..." clj-src)))
      (b/compile-clj {:basis     basis
                      :src-dirs  [clj-src]
                      :class-dir (class-dir params)})
      (update params :src-dirs conj clj-src))
    (do (when verbose (println (format "skipping clj compile, no clj-src specified...")))
        params)))

(defn- read-metadata-from-file [filename]
  (-> filename
      (slurp)
      (edn/read-string)))

(def default [d] (fn [x] (if x x d)))

(defn- process-params [base-params]
  (-> base-params
      (merge default-params)
      (merge (read-metadata-from-file
              (or (:metadata base-params)
                  "metadata.edn")))
      (update :target str)
      (update :version str)
      (update :java-src str)
      (update :clj-src str)
      (update :name str)
      (update :namespace str)
      (insert-lib-name)))

(defn write-pom [{:keys [lib version basis src-dirs verbose] :as params}]
  (let [classes (class-dir params)]
    (when verbose (println (format "writing POM file to %s...") classes))
    (b/write-pom {:class-dir classes
                  :lib       lib
                  :version   version
                  :basis     basis
                  :src-dirs  src-dirs}))
  params)

(defn- copy-src-to-target [{:keys [src-dirs] :as params}]
  (let [classes (class-dir params)]
    (when verbose (println (format "copying source files from %s to %s..."
                                   src-dirs classes)))
    (b/copy-dir {:src-dirs src-dirs :target-dir classes}))
  params)

(defn- print-params [params]
  (if (:verbose params)
    (println "parameters: ")
    (pprint params)
    (println))
  params)

(defn- finalize [params]
  (println "done!")
  params)

(defn- write-jar [{:keys [jar class-dir verbose] as params}]
  (when verbose (println "writing JAR file to %s..." jar))
  (b/jar :class-dir class-dir :jar-file jar)
  params)

(defn- write-uberjar [{:keys [verbose uberjar class-dir basis] as params}]
  (when verbose (println "writing UBERJAR file to %s..." uberjar))
  (b/uber {:class-dir class-dir :uber-file uberjar :basis basis})
  params)

(defn- install [{:keys [verbose basis lib version jar class-dir] :as params}]
  (when verbose (println (format "installing %s..." jar)))
  (b/install {:basis     basis
              :lib       lib
              :version   version
              :jar-file  jar
              :class-dir class-dir
              })
  params)

(defn jar [base-params]
  (-> params
      (process-params)
      (print-params)
      (compile-java)
      (compile-clj)
      (write-pom)
      (copy-src-to-target)
      (write-jar)
      (finalize)))

(defn uberjar [base-params]
  (-> params
      (process-params)
      (print-params)
      (compile-java)
      (compile-clj)
      (write-pom)
      (copy-src-to-target)
      (write-uberjar)
      (finalize)))

(defn install [base-params]
  (-> params
      (process-params)
      (write-jar)
      (install)))
