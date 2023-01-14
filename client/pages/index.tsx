import type { NextPage } from "next";
import styles from "../styles/Home.module.css";
import { useWallet } from "../hooks/useWallet";
import Container from "../components/Container/Container";
import Image from "next/image";

const Home: NextPage = () => {
  const { currentAccount, connectWallet } = useWallet();

  return (
    <div className={styles.pageBody}>
      <div className={styles.navBar}>
        <div className={styles.rightHeader}>
          <Image alt="Picture of icon" src="/bird.png" width={40} height={30} />
          <div className={styles.appName}> Miniswap </div>
        </div>
        {currentAccount == undefined ? (
          <div className={styles.connectBtn} onClick={connectWallet}>
            {" "}
            Connect to wallet{" "}
          </div>
        ) : (
          <div className={styles.connected}>
            {" "}
            {"Connected to " + currentAccount}{" "}
          </div>
        )}
      </div>
      <Container currentAccount={currentAccount} />
    </div>
  );
};

export default Home;