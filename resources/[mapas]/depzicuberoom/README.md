# depzicuberoom

Mapa Cuberoom Showroom com cinco salas alinhadas no eixo X.

## Coordenadas

| Sala | Centro |
|------|--------|
| Central | `vec3(0.0, 0.0, 0.0)` |
| Leste 1 | `vec3(40.0, 0.0, 0.0)` |
| Leste 2 | `vec3(80.0, 0.0, 0.0)` |
| Oeste 1 | `vec3(-40.0, 0.0, 0.0)` |
| Oeste 2 | `vec3(-80.0, 0.0, 0.0)` |

As coordenadas foram lidas diretamente das entidades dos cinco YMAPs. O ponto
`0,0,0` informado pelo autor e apenas o centro da sala principal.

`Cuberoom Props.ymap` adiciona as luzes de piso. Para mover o conjunto, todos os
YMAPs e YBNs devem receber o mesmo deslocamento.
