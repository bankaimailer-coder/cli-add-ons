# Gyakori leletek: a kódoló átadás előtt végigmegy rajta

A review-körök visszatérő leletei. A kapujelentésben pontonként: „megnéztem, rendben”, „megnéztem, nem vonatkozik, mert …”, vagy a talált hiba és a javítása. Az új visszatérő leletet a lista végére írd; a repóra nem érvényes pontot töröld, indokkal a döntésnaplóban. (MUNKAREND 2.8, gyorsítás, 2026-11-19)

1. Két kérés átfedése: két gyors egymás utáni művelet, két lap vagy kliens, a régi válasz később ér be, mint az új.
2. Ismételt kérés: ugyanaz a művelet kétszer (dupla kattintás, újrapróbálás); idempotens-e, takarít-e a második.
3. Félbeszakadás: a művelet két lépése között megszakad (két írás, írás és értesítés); mi marad, és mi takarítja.
4. Elveszett válasz: a szerver elvégezte, de a válasz nem ér vissza (időkorlát, hálózat); a kliens és a szerver mit gondol, mi maradt.
5. Hibaág teszt nélkül: minden `catch`-, elutasító és takarító ágra van-e teszt, amely egy elrontott változatra piros.
6. Gyorsítótár és idő: régi válasz a gyorsítótárból, nap- és időzónaváltás, az óra eltérése; az idő kívülről jön.
7. Jogosultság: más felhasználó, más szerep, kilépett vagy letiltott fiók mit kap; csak azt, amit a feladatlap enged.
8. Hibás bemenet: hiányos vagy sémán kívüli adat a határon (kérés, fájl, tárolt adat); néma hiba nincs.
9. A javítás saját hibája: a javítókör új ága (visszaolvasás, újrapróbálás) maga is hibázhat; ugyanezt a listát a javításra is.
10. Tesztek: a teszt a viselkedést méri, nem a forrás szövegét; a régi tesztelvárás nem gyengült.
